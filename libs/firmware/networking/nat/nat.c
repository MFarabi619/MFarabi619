/*
 * Copyright (c) 2026 Apidae Systems
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <errno.h>
#include <string.h>

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/net/ethernet.h>
#include <zephyr/net/icmp.h>
#include <zephyr/net/net_event.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/net_ip.h>
#include <zephyr/net/net_mgmt.h>
#include <zephyr/net/net_pkt.h>
#include <zephyr/net/net_pkt_filter.h>
#include <zephyr/sys/atomic.h>
#include <zephyr/sys/byteorder.h>

#include "iram.h"
#include "conntrack.h"

extern struct net_if *cellularPPPIface(void);

LOG_MODULE_REGISTER(nat, LOG_LEVEL_INF);

static inline uint16_t checksum_update_word(uint16_t old_csum_be, uint16_t old_word_be,
					    uint16_t new_word_be)
{
	uint32_t sum = (uint16_t)~old_csum_be;

	sum += (uint16_t)~old_word_be;
	sum += new_word_be;
	sum = (sum & 0xFFFF) + (sum >> 16);
	sum = (sum & 0xFFFF) + (sum >> 16);
	return (uint16_t)~sum;
}

static inline uint16_t checksum_update_long(uint16_t old_csum_be, uint32_t old_long_be,
					    uint32_t new_long_be)
{
	uint16_t partial = checksum_update_word(old_csum_be, (uint16_t)(old_long_be >> 16),
						(uint16_t)(new_long_be >> 16));
	return checksum_update_word(partial, (uint16_t)(old_long_be & 0xFFFF),
				    (uint16_t)(new_long_be & 0xFFFF));
}

/* PPP MTU is 1500 (CONFIG_NET_PPP_MTU_MRU default). Clamp TCP MSS to
 * 1400 = 1440 + 20 (IPv4) + 20 (TCP). Leaves 60-byte margin under cellular
 * MTU since LTE-M carriers often advertise 1428 instead of 1500; main win
 * is reducing fragmentation/retransmit on Tailscale DERP (TLS-over-TCP)
 * relayed traffic, where every byte traverses the cellular uplink.
 */
#define NAT_MSS_CLAMP 1400

#define TCP_OFFSET_FLAGS    13
#define TCP_OFFSET_DATA_OFF 12
#define TCP_FLAG_SYN        0x02
#define TCP_OPT_END         0
#define TCP_OPT_NOP         1
#define TCP_OPT_MSS         2
#define TCP_OPT_MSS_LEN     4

/* ICMP echo identifier lives past the 4-byte net_icmp_hdr (type/code/chksum).
 * Zephyr doesn't expose a struct for echo extensions, so the offset stays
 * as a named constant. Type field uses struct net_icmp_hdr accessor directly.
 */
#define ICMP_OFFSET_IDENTIFIER 4

static IRAM_HOT void clamp_tcp_mss(uint8_t *l4_header, uint16_t max_mss, uint16_t *l4_chksum)
{
	if ((l4_header[TCP_OFFSET_FLAGS] & TCP_FLAG_SYN) == 0) {
		return;
	}

	uint8_t header_words = FIELD_GET(0xF0, l4_header[TCP_OFFSET_DATA_OFF]);
	uint8_t header_bytes = header_words * 4;

	if (header_bytes <= 20) {
		return;
	}

	uint8_t *options = l4_header + 20;
	uint8_t *options_end = l4_header + header_bytes;

	while (options < options_end) {
		uint8_t kind = options[0];

		if (kind == TCP_OPT_END) {
			return;
		}
		if (kind == TCP_OPT_NOP) {
			options++;
			continue;
		}
		if ((options + 1) >= options_end) {
			return;
		}
		uint8_t opt_len = options[1];

		if (opt_len < 2 || (options + opt_len) > options_end) {
			return;
		}
		if (kind == TCP_OPT_MSS && opt_len == TCP_OPT_MSS_LEN) {
			uint16_t old_mss_be = *(uint16_t *)&options[2];

			if (sys_be16_to_cpu(old_mss_be) > max_mss) {
				uint16_t new_mss_be = sys_cpu_to_be16(max_mss);

				if (l4_chksum != NULL) {
					*l4_chksum = checksum_update_word(*l4_chksum, old_mss_be,
									  new_mss_be);
				}
				*(uint16_t *)&options[2] = new_mss_be;
			}
			return;
		}
		options += opt_len;
	}
}

static struct net_if *access_point_iface;
static struct net_if *cellular_iface;

static struct k_work_delayable reap_work;

static atomic_t cellular_address_cached_be = ATOMIC_INIT(0);
static atomic_t is_cellular_address_valid = ATOMIC_INIT(0);

static void on_cellular_addr_change(uint64_t event, struct net_if *iface, void *info,
				    size_t info_length, void *user_data)
{
	ARG_UNUSED(info);
	ARG_UNUSED(info_length);
	ARG_UNUSED(user_data);

	if (cellular_iface == NULL || iface != cellular_iface) {
		return;
	}

	if (event == NET_EVENT_IPV4_ADDR_ADD) {
		const struct in_addr *addr =
			net_if_ipv4_get_global_addr(cellular_iface, NET_ADDR_PREFERRED);

		if (addr != NULL) {
			atomic_set(&cellular_address_cached_be, (atomic_val_t)addr->s_addr);
			atomic_set(&is_cellular_address_valid, 1);
		}
	} else if (event == NET_EVENT_IPV4_ADDR_DEL) {
		atomic_set(&is_cellular_address_valid, 0);
	}
}

NET_MGMT_REGISTER_EVENT_HANDLER(nat_cellular_addr_cb,
				NET_EVENT_IPV4_ADDR_ADD | NET_EVENT_IPV4_ADDR_DEL,
				on_cellular_addr_change, NULL);

static IRAM_HOT uint8_t ipv4_header_length(const struct net_ipv4_hdr *header)
{
	return FIELD_GET(0x0f, header->vhl) * 4;
}

static IRAM_HOT uint16_t *l4_checksum_ptr(struct net_ipv4_hdr *header, uint8_t *l4_header)
{
	switch (header->proto) {
	case IPPROTO_TCP:
		return &((struct net_tcp_hdr *)l4_header)->chksum;
	case IPPROTO_UDP:
		return &((struct net_udp_hdr *)l4_header)->chksum;
	default:
		return NULL;
	}
}

static IRAM_HOT void mutate_and_send(struct net_pkt *pkt, struct net_if *target_iface)
{
	memset(net_pkt_lladdr_src(pkt), 0, sizeof(struct net_linkaddr));
	memset(net_pkt_lladdr_dst(pkt), 0, sizeof(struct net_linkaddr));
	net_pkt_set_ll_proto_type(pkt, NET_ETH_PTYPE_IP);
	net_pkt_set_iface(pkt, target_iface);

	net_if_queue_tx(target_iface, pkt);

	LOG_DBG("queued tx on iface %d", net_if_get_by_iface(target_iface));
}

static IRAM_HOT bool outbound_predicate(struct npf_test *test, struct net_pkt *pkt)
{
	ARG_UNUSED(test);

	struct net_ipv4_hdr *header = NET_IPV4_HDR(pkt);
	struct in_addr dst_addr;

	memcpy(&dst_addr, header->dst, sizeof(dst_addr));

	if (net_if_ipv4_addr_mask_cmp(access_point_iface, &dst_addr) ||
	    net_ipv4_is_addr_bcast(access_point_iface, &dst_addr) ||
	    net_ipv4_is_addr_mcast(&dst_addr)) {
		return false;
	}

	if (header->proto != IPPROTO_TCP && header->proto != IPPROTO_UDP &&
	    header->proto != IPPROTO_ICMP) {
		return false;
	}

	if (!atomic_get(&is_cellular_address_valid)) {
		return false;
	}

	uint8_t *l4_header = (uint8_t *)header + ipv4_header_length(header);
	uint16_t old_src_port_be;
	uint16_t dst_port_be;

	if (header->proto == IPPROTO_ICMP) {
		if (((struct net_icmp_hdr *)l4_header)->type != NET_ICMPV4_ECHO_REQUEST) {
			return false;
		}
		uint16_t icmp_id = *(uint16_t *)&l4_header[ICMP_OFFSET_IDENTIFIER];

		old_src_port_be = icmp_id;
		dst_port_be = icmp_id;
	} else {
		const struct net_udp_hdr *udp = (const struct net_udp_hdr *)l4_header;

		old_src_port_be = udp->src_port;
		dst_port_be = udp->dst_port;
	}

	uint32_t old_src_ip_be;
	uint32_t dst_ip_be;

	memcpy(&old_src_ip_be, header->src, 4);
	memcpy(&dst_ip_be, header->dst, 4);

	struct ConntrackEntry *entry = conntrackLookupOutbound(
		header->proto, old_src_ip_be, old_src_port_be, dst_ip_be, dst_port_be);
	if (entry == NULL) {
		return false;
	}

	uint32_t new_src_ip_be = (uint32_t)atomic_get(&cellular_address_cached_be);
	uint16_t new_src_port_be = entry->nat_port;

	header->chksum = checksum_update_long(header->chksum, old_src_ip_be, new_src_ip_be);

	uint16_t *l4_chksum = l4_checksum_ptr(header, l4_header);

	if (l4_chksum != NULL && !(header->proto == IPPROTO_UDP && *l4_chksum == 0)) {
		uint16_t running_checksum =
			checksum_update_long(*l4_chksum, old_src_ip_be, new_src_ip_be);

		running_checksum = checksum_update_word(running_checksum, old_src_port_be,
							new_src_port_be);
		if (header->proto == IPPROTO_UDP && running_checksum == 0) {
			running_checksum = 0xFFFF;
		}
		*l4_chksum = running_checksum;
	}

	memcpy(header->src, &new_src_ip_be, 4);
	if (header->proto != IPPROTO_ICMP) {
		((struct net_udp_hdr *)l4_header)->src_port = new_src_port_be;
	}

	if (header->proto == IPPROTO_TCP) {
		clamp_tcp_mss(l4_header, NAT_MSS_CLAMP, l4_chksum);
	}

	net_pkt_ref(pkt);
	mutate_and_send(pkt, cellular_iface);
	return true;
}

static IRAM_HOT bool return_predicate(struct npf_test *test, struct net_pkt *pkt)
{
	ARG_UNUSED(test);

	struct net_ipv4_hdr *header = NET_IPV4_HDR(pkt);

	if (header->proto != IPPROTO_TCP && header->proto != IPPROTO_UDP &&
	    header->proto != IPPROTO_ICMP) {
		return false;
	}

	uint8_t *l4_header = (uint8_t *)header + ipv4_header_length(header);
	uint16_t nat_port_be;
	uint16_t remote_port_be;

	if (header->proto == IPPROTO_ICMP) {
		if (((struct net_icmp_hdr *)l4_header)->type != NET_ICMPV4_ECHO_REPLY) {
			return false;
		}
		nat_port_be = *(uint16_t *)&l4_header[ICMP_OFFSET_IDENTIFIER];
		remote_port_be = nat_port_be;
	} else {
		const struct net_udp_hdr *udp = (const struct net_udp_hdr *)l4_header;

		nat_port_be = udp->dst_port;
		remote_port_be = udp->src_port;
	}

	uint32_t remote_ip_be;

	memcpy(&remote_ip_be, header->src, 4);

	struct ConntrackEntry *entry =
		conntrackLookupInbound(header->proto, nat_port_be, remote_ip_be, remote_port_be);

	if (entry == NULL) {
		LOG_DBG("return RX: proto=%u dst_port=%u match=no", header->proto,
			sys_be16_to_cpu(nat_port_be));
		return false;
	}

	uint32_t old_dst_ip_be;

	memcpy(&old_dst_ip_be, header->dst, 4);

	uint32_t new_dst_ip_be = entry->client_ip;
	uint16_t new_dst_port_be = entry->client_port;

	header->chksum = checksum_update_long(header->chksum, old_dst_ip_be, new_dst_ip_be);

	uint16_t *l4_chksum = l4_checksum_ptr(header, l4_header);

	if (l4_chksum != NULL && !(header->proto == IPPROTO_UDP && *l4_chksum == 0)) {
		uint16_t running_checksum =
			checksum_update_long(*l4_chksum, old_dst_ip_be, new_dst_ip_be);

		running_checksum = checksum_update_word(running_checksum, nat_port_be,
							new_dst_port_be);
		if (header->proto == IPPROTO_UDP && running_checksum == 0) {
			running_checksum = 0xFFFF;
		}
		*l4_chksum = running_checksum;
	}

	memcpy(header->dst, &new_dst_ip_be, 4);
	if (header->proto != IPPROTO_ICMP) {
		((struct net_udp_hdr *)l4_header)->dst_port = new_dst_port_be;
	}

	if (header->proto == IPPROTO_TCP) {
		clamp_tcp_mss(l4_header, NAT_MSS_CLAMP, l4_chksum);
	}

	net_pkt_ref(pkt);
	mutate_and_send(pkt, access_point_iface);
	return true;
}

struct nat_predicate_wrapper {
	struct npf_test test;
};

static struct nat_predicate_wrapper outbound_predicate_obj = {
	.test.fn = outbound_predicate,
};

static struct nat_predicate_wrapper return_predicate_obj = {
	.test.fn = return_predicate,
};

NPF_IFACE_MATCH(nat_match_iface_ap, NULL);
NPF_IFACE_MATCH(nat_match_iface_cell, NULL);

NPF_RULE(nat_outbound_rule, NET_DROP, nat_match_iface_ap, outbound_predicate_obj);
NPF_RULE(nat_return_rule, NET_DROP, nat_match_iface_cell, return_predicate_obj);

static void reap_handler(struct k_work *work)
{
	ARG_UNUSED(work);
	conntrackReapIdle(k_uptime_get());
	k_work_schedule(&reap_work, K_SECONDS(10));
}

int natInitialize(void)
{
	struct net_if *ap_iface = net_if_get_wifi_sap();
	struct net_if *cell_iface = cellularPPPIface();

	if (ap_iface == NULL || cell_iface == NULL) {
		return -ENODEV;
	}
	access_point_iface = ap_iface;
	cellular_iface = cell_iface;
	nat_match_iface_ap.iface = ap_iface;
	nat_match_iface_cell.iface = cell_iface;

	const struct in_addr *initial_addr =
		net_if_ipv4_get_global_addr(cell_iface, NET_ADDR_PREFERRED);

	if (initial_addr != NULL) {
		atomic_set(&cellular_address_cached_be, (atomic_val_t)initial_addr->s_addr);
		atomic_set(&is_cellular_address_valid, 1);
	}

	conntrackInitialize();

	k_work_init_delayable(&reap_work, reap_handler);

	npf_append_ipv4_recv_rule(&nat_outbound_rule);
	npf_append_ipv4_recv_rule(&nat_return_rule);
	npf_append_ipv4_recv_rule(&npf_default_ok);

	k_work_schedule(&reap_work, K_SECONDS(10));

	LOG_INF("NAT armed: AP=%p cellular=%p (TCP+UDP+ICMP, conntrack=%d entries)", ap_iface,
		cell_iface, CONNTRACK_SIZE);
	return 0;
}
