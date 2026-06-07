/*
 * Copyright (c) 2026 Apidae Systems
 * SPDX-License-Identifier: Apache-2.0
 */

#include <errno.h>
#include <string.h>

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/net_ip.h>
#include <zephyr/net/socket.h>
#include <zephyr/net/virtual.h>
#include <zephyr/net/virtual_mgmt.h>
#include <zephyr/net/wireguard.h>
#include <zephyr/sys/base64.h>
#include <zephyr/sys/byteorder.h>

#include "snapshot.h"
#include "wg_internal.h"

LOG_MODULE_REGISTER(wireguard, LOG_LEVEL_INF);

static struct net_if *vpn_iface(void)
{
	return net_if_get_first_by_type(&NET_L2_GET_NAME(VIRTUAL));
}

static int parse_v4_cidr(const char *cidr, size_t cidr_len,
			 struct net_in_addr *out_addr, uint8_t *out_mask_len)
{
	struct net_sockaddr_storage storage = {0};
	struct net_sockaddr *parsed = (struct net_sockaddr *)&storage;
	char cidr_buffer[NET_IPV4_ADDR_LEN + 4];

	if (cidr_len == 0 || cidr_len >= sizeof(cidr_buffer)) {
		return -EINVAL;
	}
	memcpy(cidr_buffer, cidr, cidr_len);
	cidr_buffer[cidr_len] = '\0';

	if (net_ipaddr_parse_mask(cidr_buffer, cidr_len, parsed, out_mask_len) == NULL) {
		return -EINVAL;
	}
	if (parsed->sa_family != NET_AF_INET) {
		return -EAFNOSUPPORT;
	}
	*out_addr = net_sin(parsed)->sin_addr;
	return 0;
}

int wireguard_set_private_key(const char *b64, size_t b64_len)
{
	struct net_if *vpn = vpn_iface();
	struct virtual_interface_req_params params = {0};
	uint8_t key[NET_VIRTUAL_MAX_PUBLIC_KEY_LEN];
	size_t olen;
	int ret;

	if (vpn == NULL) {
		return -ENODEV;
	}

	ret = base64_decode(key, sizeof(key), &olen, (const uint8_t *)b64, b64_len);
	if (ret < 0) {
		LOG_ERR("base64_decode failed (%d)", ret);
		return ret;
	}
	params.private_key.data = key;
	params.private_key.len = sizeof(key);
	ret = net_mgmt(NET_REQUEST_VIRTUAL_INTERFACE_SET_PRIVATE_KEY,
		       vpn, &params, sizeof(params));
	memset(key, 0, sizeof(key));
	return ret;
}

int wireguard_log_public_key(void)
{
	struct net_if *vpn = vpn_iface();
	struct virtual_interface_req_params params = {0};
	char b64[NET_VIRTUAL_MAX_PUBLIC_KEY_LEN * 2];
	size_t olen;
	int ret;

	if (vpn == NULL) {
		return -ENODEV;
	}
	ret = net_mgmt(NET_REQUEST_VIRTUAL_INTERFACE_GET_PUBLIC_KEY,
		       vpn, &params, sizeof(params));
	if (ret < 0) {
		return ret;
	}
	if (base64_encode(b64, sizeof(b64), &olen,
			  params.public_key.data, params.public_key.len) != 0) {
		return -EIO;
	}
	LOG_INF("local public key: %s", b64);
	return 0;
}

int wireguard_assign_local_addr(const char *cidr, size_t cidr_len)
{
	struct net_if *vpn = vpn_iface();
	struct net_in_addr addr;
	struct net_sockaddr_in mask_sa = {0};
	uint8_t mask_len = 0;
	int ret;

	if (vpn == NULL) {
		return -ENODEV;
	}

	ret = parse_v4_cidr(cidr, cidr_len, &addr, &mask_len);
	if (ret < 0) {
		LOG_ERR("local cidr parse failed (%d)", ret);
		return ret;
	}
	if (net_if_ipv4_addr_add(vpn, &addr, NET_ADDR_MANUAL, 0) == NULL) {
		LOG_ERR("addr_add failed");
		return -ENOENT;
	}
	if (net_mask_len_to_netmask(NET_AF_INET, mask_len,
				    (struct net_sockaddr *)&mask_sa) < 0) {
		return -EINVAL;
	}
	(void)net_if_ipv4_set_netmask_by_addr(vpn, &addr, &mask_sa.sin_addr);
	return 0;
}

int wireguard_bring_interface_up(void)
{
	struct net_if *vpn = vpn_iface();

	if (vpn == NULL) {
		return -ENODEV;
	}
	net_virtual_set_name(vpn, "wg0");
	if (net_if_is_up(vpn)) {
		return 0;
	}
	return net_if_up(vpn);
}

int wireguard_add_peer(const char *pubkey, size_t pubkey_len,
		     const char *endpoint, size_t endpoint_len,
		     const char *allowed_cidr, size_t allowed_cidr_len,
		     int keepalive_seconds)
{
	struct wireguard_peer_config peer = {0};
	struct net_sockaddr_storage storage = {0};
	struct net_sockaddr *parsed = (struct net_sockaddr *)&storage;
	struct net_if *peer_iface = NULL;
	struct net_in_addr allowed_addr;
	char pubkey_buffer[64];
	char endpoint_buffer[64];
	uint8_t mask_len = 0;
	int ret;

	if (pubkey_len == 0 || pubkey_len >= sizeof(pubkey_buffer)) {
		return -EINVAL;
	}
	memcpy(pubkey_buffer, pubkey, pubkey_len);
	pubkey_buffer[pubkey_len] = '\0';

	if (endpoint_len == 0 || endpoint_len >= sizeof(endpoint_buffer)) {
		return -EINVAL;
	}
	memcpy(endpoint_buffer, endpoint, endpoint_len);
	endpoint_buffer[endpoint_len] = '\0';

	peer.public_key = pubkey_buffer;
	peer.keepalive_interval = keepalive_seconds;

	if (!net_ipaddr_parse(endpoint_buffer, endpoint_len, parsed) ||
	    parsed->sa_family != NET_AF_INET) {
		LOG_ERR("endpoint parse failed");
		return -EINVAL;
	}
	memcpy(&peer.endpoint_ip, parsed, sizeof(struct net_sockaddr_in));

	ret = parse_v4_cidr(allowed_cidr, allowed_cidr_len, &allowed_addr, &mask_len);
	if (ret < 0) {
		LOG_ERR("allowed cidr parse failed (%d)", ret);
		return ret;
	}
	peer.allowed_ip[0].is_valid = true;
	peer.allowed_ip[0].mask_len = mask_len;
	peer.allowed_ip[0].addr.family = NET_AF_INET;
	memcpy(&peer.allowed_ip[0].addr.in_addr, &allowed_addr, sizeof(allowed_addr));

	ret = wireguard_peer_add(&peer, &peer_iface);
	if (ret < 0) {
		LOG_ERR("wireguard_peer_add failed (%d)", ret);
		return ret;
	}
	LOG_INF("peer id=%d iface=%d", ret,
		peer_iface ? net_if_get_by_iface(peer_iface) : -1);
	return 0;
}

int wireguard_kickoff_handshake(const char *peer_addr, size_t peer_addr_len)
{
	struct net_sockaddr_storage storage = {0};
	struct net_sockaddr *parsed = (struct net_sockaddr *)&storage;
	char peer_addr_buffer[NET_IPV4_ADDR_LEN + 1];
	const uint8_t payload = 0;
	int udp_socket;
	int send_result;

	if (peer_addr_len == 0 || peer_addr_len >= sizeof(peer_addr_buffer)) {
		return -EINVAL;
	}
	memcpy(peer_addr_buffer, peer_addr, peer_addr_len);
	peer_addr_buffer[peer_addr_len] = '\0';

	if (!net_ipaddr_parse(peer_addr_buffer, peer_addr_len, parsed) ||
	    parsed->sa_family != NET_AF_INET) {
		LOG_ERR("kickoff: parse %s failed", peer_addr_buffer);
		return -EINVAL;
	}
	net_sin(parsed)->sin_port = sys_cpu_to_be16(9);

	udp_socket = zsock_socket(NET_AF_INET, NET_SOCK_DGRAM, NET_IPPROTO_UDP);
	if (udp_socket < 0) {
		return -errno;
	}
	send_result = zsock_sendto(udp_socket, &payload, sizeof(payload), 0,
				   parsed, sizeof(struct net_sockaddr_in));
	zsock_close(udp_socket);

	if (send_result < 0 && errno != EAGAIN) {
		LOG_ERR("kickoff sendto: errno %d", errno);
		return -errno;
	}
	LOG_INF("handshake kickoff sent via %s", peer_addr_buffer);
	return 0;
}

static void fill_peer_snapshot(struct wg_peer *peer, void *user_data)
{
	struct wg_snapshot *snapshot = user_data;
	struct wg_peer_snapshot *out;
	size_t encoded_len;
	uint32_t now;

	if (snapshot->peer_count >= ARRAY_SIZE(snapshot->peers)) {
		return;
	}
	out = &snapshot->peers[snapshot->peer_count++];
	out->valid = true;
	out->id = peer->id;
	out->iface_index = peer->iface ? net_if_get_by_iface(peer->iface) : -1;
	out->keepalive_seconds = peer->keepalive_interval;

	(void)base64_encode(out->public_key_b64, sizeof(out->public_key_b64),
			    &encoded_len,
			    peer->key.public_key, sizeof(peer->key.public_key));

	if (peer->cfg_endpoint.ss_family == NET_AF_INET) {
		char addr[NET_IPV4_ADDR_LEN + 1];

		net_addr_ntop(NET_AF_INET,
			      &net_sin(net_sad(&peer->cfg_endpoint))->sin_addr,
			      addr, sizeof(addr));
		snprintk(out->endpoint, sizeof(out->endpoint), "%s:%u", addr,
			 net_ntohs(net_sin(net_sad(&peer->cfg_endpoint))->sin_port));
	}

	if (peer->allowed_ip[0].is_valid &&
	    peer->allowed_ip[0].addr.family == NET_AF_INET) {
		char addr[NET_IPV4_ADDR_LEN + 1];

		net_addr_ntop(NET_AF_INET, &peer->allowed_ip[0].addr.in_addr,
			      addr, sizeof(addr));
		snprintk(out->allowed_cidr, sizeof(out->allowed_cidr), "%s/%u",
			 addr, peer->allowed_ip[0].mask_len);
	}

	now = sys_clock_tick_get_32();
	if (peer->last_initiation_tx) {
		out->last_handshake_age_sec =
			k_ticks_to_sec_floor32(now - peer->last_initiation_tx);
	}
	if (peer->last_tx) {
		out->last_tx_age_sec =
			k_ticks_to_sec_floor32(now - peer->last_tx);
	}
	if (peer->last_rx) {
		out->last_rx_age_sec =
			k_ticks_to_sec_floor32(now - peer->last_rx);
	}
}

int wireguard_access_snapshot(struct wg_snapshot *snapshot)
{
	struct net_if *vpn;
	struct virtual_interface_req_params params = {0};
	size_t encoded_len;

	if (snapshot == NULL) {
		return -EINVAL;
	}
	memset(snapshot, 0, sizeof(*snapshot));

	vpn = vpn_iface();
	if (vpn == NULL) {
		return -ENODEV;
	}
	snapshot->iface_up = net_if_is_up(vpn);

	if (net_mgmt(NET_REQUEST_VIRTUAL_INTERFACE_GET_PUBLIC_KEY,
		     vpn, &params, sizeof(params)) == 0) {
		(void)base64_encode(snapshot->local_public_key_b64,
				    sizeof(snapshot->local_public_key_b64),
				    &encoded_len,
				    params.public_key.data,
				    params.public_key.len);
	}

	wireguard_peer_foreach(fill_peer_snapshot, snapshot);
	return 0;
}
