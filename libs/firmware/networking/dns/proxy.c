#include <errno.h>
#include <string.h>

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/net_buf.h>
#include <zephyr/net/dns_resolve.h>
#include <zephyr/net/socket.h>
#include <zephyr/net/socket_service.h>
#include <zephyr/sys/byteorder.h>

#include "dns_pack.h"
#include "proxy.h"

LOG_MODULE_REGISTER(dns_proxy, LOG_LEVEL_INF);

#define DNS_PROXY_PORT          53
#define DNS_PROXY_BUF_SIZE      512
#define DNS_PROXY_TIMEOUT_MS    4000
#define DNS_PROXY_PENDING_DEADLINE_MS (DNS_PROXY_TIMEOUT_MS * 2)
#define DNS_PROXY_TTL           60
#define DNS_PROXY_MAX_ANS       4
#define DNS_PROXY_QUESTION_MAX  (DNS_NAME_MAX_SIZE + DNS_QTYPE_LEN + DNS_QCLASS_LEN)

enum DNSDecision {
	DNS_DECISION_ANSWER  = 0,
	DNS_DECISION_BLOCK   = 1,
	DNS_DECISION_EMPTY   = 2,
	DNS_DECISION_FORWARD = 3,
};

extern int dns_decide(const char *name, uint16_t qtype, uint32_t *out_ip_be);

NET_BUF_POOL_DEFINE(dns_msg_pool, 1, DNS_NAME_MAX_SIZE, 0, NULL);

struct DNSPending {
	struct sockaddr_in client;
	char     qname[DNS_NAME_MAX_SIZE + 1];
	uint8_t  question[DNS_PROXY_QUESTION_MAX];
	uint16_t question_len;
	uint16_t txn_id;
	uint16_t qtype;
	uint32_t answers[DNS_PROXY_MAX_ANS];
	uint8_t  answer_count;
	bool     rd;
	bool     in_use;
	int64_t  deadline_ms;
	uint8_t  generation;
};

#define DNS_PROXY_MAX_PENDING 16
static struct DNSPending pending[DNS_PROXY_MAX_PENDING];
static int proxy_sock = -1;

static inline uintptr_t pending_make_token(uint8_t slot, uint8_t generation)
{
	return ((uintptr_t)generation << 16) | (uintptr_t)slot;
}

static inline bool pending_token_resolve(uintptr_t token, uint8_t *out_slot)
{
	uint16_t slot = token & 0xFFFF;
	uint8_t gen = (token >> 16) & 0xFF;

	if (slot >= ARRAY_SIZE(pending) || pending[slot].generation != gen) {
		return false;
	}
	*out_slot = (uint8_t)slot;
	return true;
}

static int pending_alloc(void)
{
	int64_t now = k_uptime_get();

	for (size_t i = 0; i < ARRAY_SIZE(pending); i++) {
		if (!pending[i].in_use) {
			pending[i].in_use = true;
			pending[i].deadline_ms = now + DNS_PROXY_PENDING_DEADLINE_MS;
			pending[i].answer_count = 0;
			return (int)i;
		}
	}
	for (size_t i = 0; i < ARRAY_SIZE(pending); i++) {
		if (pending[i].in_use && now >= pending[i].deadline_ms) {
			LOG_WRN("evicting wedged pending slot %zu (%s)", i, pending[i].qname);
			pending[i].generation++;
			pending[i].deadline_ms = now + DNS_PROXY_PENDING_DEADLINE_MS;
			pending[i].answer_count = 0;
			return (int)i;
		}
	}
	return -1;
}

static void build_response(struct net_buf_simple *out, uint16_t txn_id, uint16_t qtype,
			   bool rd, bool authoritative, uint8_t rcode,
			   const uint8_t *question, size_t question_len,
			   const uint32_t *answers_be, uint8_t answer_count)
{
	uint16_t flags = BIT(15);
	if (rd)            flags |= BIT(8);
	flags |= BIT(7);
	if (authoritative) flags |= BIT(10);
	flags |= (rcode & 0x0f);

	uint16_t ancount = (rcode == DNS_HEADER_NOERROR) ? answer_count : 0;

	net_buf_simple_add_be16(out, txn_id);
	net_buf_simple_add_be16(out, flags);
	net_buf_simple_add_be16(out, 1);
	net_buf_simple_add_be16(out, ancount);
	net_buf_simple_add_be16(out, 0);
	net_buf_simple_add_be16(out, 0);

	net_buf_simple_add_mem(out, question, question_len);

	for (uint8_t i = 0; i < ancount; i++) {
		if (net_buf_simple_tailroom(out) < DNS_POINTER_SIZE + DNS_QTYPE_LEN +
		    DNS_QCLASS_LEN + DNS_TTL_LEN + DNS_RDLENGTH_LEN + 4) {
			break;
		}
		net_buf_simple_add_u8(out, NS_CMPRSFLGS | ((DNS_MSG_HEADER_SIZE >> 8) & 0x3f));
		net_buf_simple_add_u8(out, DNS_MSG_HEADER_SIZE & 0xff);
		net_buf_simple_add_be16(out, qtype);
		net_buf_simple_add_be16(out, DNS_CLASS_IN);
		net_buf_simple_add_be32(out, DNS_PROXY_TTL);
		net_buf_simple_add_be16(out, 4);
		net_buf_simple_add_mem(out, &answers_be[i], 4);
	}
}

static void send_response(const struct sockaddr_in *client, uint16_t txn_id, uint16_t qtype,
			  bool rd, bool authoritative, uint8_t rcode,
			  const uint8_t *question, size_t question_len,
			  const uint32_t *answers_be, uint8_t answer_count)
{
	NET_BUF_SIMPLE_DEFINE(out, DNS_PROXY_BUF_SIZE);

	build_response(&out, txn_id, qtype, rd, authoritative, rcode,
		       question, question_len, answers_be, answer_count);

	int rc = zsock_sendto(proxy_sock, out.data, out.len, 0,
			      (const struct sockaddr *)client, sizeof(*client));
	if (rc < 0) {
		LOG_WRN("sendto: %d", errno);
	}
}

static void resolve_cb(enum dns_resolve_status status, struct dns_addrinfo *info,
		       void *user_data)
{
	uint8_t slot;

	if (!pending_token_resolve((uintptr_t)user_data, &slot)) {
		return;
	}
	struct DNSPending *p = &pending[slot];

	if (status == DNS_EAI_INPROGRESS && info != NULL &&
	    info->ai_family == NET_AF_INET) {
		if (p->answer_count < DNS_PROXY_MAX_ANS) {
			struct sockaddr_in *sa = (struct sockaddr_in *)&info->ai_addr;
			memcpy(&p->answers[p->answer_count], &sa->sin_addr, 4);
			p->answer_count++;
		}
		return;
	}

	uint8_t rcode = (status == DNS_EAI_ALLDONE && p->answer_count > 0)
				? DNS_HEADER_NOERROR
		      : (status == DNS_EAI_ALLDONE) ? DNS_HEADER_NAMEERROR
						    : DNS_HEADER_SERVERFAILURE;

	send_response(&p->client, p->txn_id, p->qtype, p->rd, false, rcode,
		      p->question, p->question_len, p->answers, p->answer_count);
	p->in_use = false;
}

static void handle_query(uint8_t *rx_buf, size_t rx_len, const struct sockaddr_in *client)
{
	if (rx_len < DNS_MSG_HEADER_SIZE) {
		return;
	}

	struct dns_msg_t dns_msg = DNS_MSG_INIT(rx_buf, MIN(rx_len, DNS_PROXY_BUF_SIZE));

	uint16_t txn_id = 0;
	int qdcount = mdns_unpack_query_header(&dns_msg, &txn_id);
	if (qdcount != 1) {
		return;
	}

	struct net_buf *qname = net_buf_alloc(&dns_msg_pool, K_NO_WAIT);
	if (!qname) {
		LOG_WRN("qname pool exhausted");
		return;
	}

	enum dns_rr_type qtype;
	enum dns_class qclass;
	int qname_len = dns_unpack_query(&dns_msg, qname, &qtype, &qclass);
	if (qname_len < 0 || qclass != DNS_CLASS_IN) {
		goto out;
	}

	size_t question_len = dns_msg.query_offset - DNS_MSG_HEADER_SIZE;
	if (question_len > DNS_PROXY_QUESTION_MAX) {
		goto out;
	}
	const uint8_t *question = rx_buf + DNS_MSG_HEADER_SIZE;
	bool rd = dns_header_rd(rx_buf);

	uint32_t answer_ip_be = 0;
	int decision = dns_decide((const char *)qname->data,
				       (uint16_t)qtype, &answer_ip_be);

	switch (decision) {
	case DNS_DECISION_ANSWER:
		send_response(client, txn_id, (uint16_t)qtype, rd, true,
			      DNS_HEADER_NOERROR, question, question_len,
			      &answer_ip_be, 1);
		break;
	case DNS_DECISION_BLOCK:
		LOG_INF("blocked: %s", (const char *)qname->data);
		send_response(client, txn_id, (uint16_t)qtype, rd, true,
			      DNS_HEADER_NAMEERROR, question, question_len,
			      NULL, 0);
		break;
	case DNS_DECISION_EMPTY:
		send_response(client, txn_id, (uint16_t)qtype, rd, false,
			      DNS_HEADER_NOERROR, question, question_len,
			      NULL, 0);
		break;
	case DNS_DECISION_FORWARD: {
		int slot = pending_alloc();
		if (slot < 0) {
			LOG_WRN("pending exhausted");
			send_response(client, txn_id, (uint16_t)qtype, rd, false,
				      DNS_HEADER_SERVERFAILURE, question, question_len,
				      NULL, 0);
			break;
		}
		struct DNSPending *p = &pending[slot];
		memcpy(&p->client, client, sizeof(*client));
		memcpy(p->qname, qname->data, qname->len);
		p->qname[qname->len] = '\0';
		memcpy(p->question, question, question_len);
		p->question_len = (uint16_t)question_len;
		p->txn_id = txn_id;
		p->qtype = (uint16_t)qtype;
		p->rd = rd;
		p->answer_count = 0;

		uintptr_t token = pending_make_token((uint8_t)slot, p->generation);
		uint16_t resolve_id;
		int rc = dns_get_addr_info(p->qname, DNS_QUERY_TYPE_A, &resolve_id,
					   resolve_cb, (void *)token,
					   DNS_PROXY_TIMEOUT_MS);
		if (rc < 0) {
			LOG_WRN("dns_get_addr_info: %d", rc);
			send_response(client, txn_id, (uint16_t)qtype, rd, false,
				      DNS_HEADER_SERVERFAILURE, question, question_len,
				      NULL, 0);
			p->in_use = false;
		}
		break;
	}
	}

out:
	net_buf_unref(qname);
}

static void dns_proxy_event_cb(struct net_socket_service_event *evt)
{
	if (!(evt->event.revents & ZSOCK_POLLIN)) {
		return;
	}

	static uint8_t buf[DNS_PROXY_BUF_SIZE];
	static struct sockaddr_in from;
	socklen_t from_len = sizeof(from);

	int n = zsock_recvfrom(evt->event.fd, buf, sizeof(buf), 0,
			       (struct sockaddr *)&from, &from_len);
	if (n < 0) {
		LOG_WRN("recvfrom: %d", errno);
		return;
	}
	handle_query(buf, n, &from);
}

NET_SOCKET_SERVICE_SYNC_DEFINE_STATIC(dns_proxy_service, dns_proxy_event_cb, 1);

int dns_proxy_initialize(void)
{
	proxy_sock = zsock_socket(NET_AF_INET, NET_SOCK_DGRAM, NET_IPPROTO_UDP);
	if (proxy_sock < 0) {
		LOG_ERR("socket: %d", errno);
		return -errno;
	}

	struct sockaddr_in bind_addr = {
		.sin_family = NET_AF_INET,
		.sin_port = htons(DNS_PROXY_PORT),
		.sin_addr.s_addr = htonl(NET_INADDR_ANY),
	};

	if (zsock_bind(proxy_sock, (struct sockaddr *)&bind_addr, sizeof(bind_addr)) < 0) {
		LOG_ERR("bind :53 failed: %d", errno);
		zsock_close(proxy_sock);
		proxy_sock = -1;
		return -errno;
	}

	static struct zsock_pollfd fds = {.events = ZSOCK_POLLIN};
	fds.fd = proxy_sock;
	net_socket_service_register(&dns_proxy_service, &fds, 1, NULL);

	LOG_INF("DNS proxy listening on UDP/53 (cache: %d entries)",
		CONFIG_DNS_RESOLVER_CACHE_MAX_ENTRIES);
	return 0;
}
