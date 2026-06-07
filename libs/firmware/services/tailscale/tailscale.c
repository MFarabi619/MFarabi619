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

LOG_MODULE_REGISTER(tailscale, LOG_LEVEL_INF);

#define LOCAL_PRIVATE_KEY_B64  "mO1EiP9jTcRLFxP/GQlrtvdmDHv39e1sevI8PRehY00="
#define LOCAL_TUNNEL_CIDR      "10.10.10.2/24"
#define PEER_PUBLIC_KEY_B64    "bBk3IoOmGxRJwPLCYl0QyoM/J74D+Pt72Q5mLxIiDmQ="
#define PEER_ALLOWED_CIDR      "10.10.10.0/24"
#define PEER_ENDPOINT          "10.0.0.162:51820"
#define PEER_TUNNEL_ADDR       "10.10.10.1"
#define HELLO_PORT             4242
#define HELLO_MSG              "hello via wg\n"
#define KEEPALIVE_SECONDS      25
#define UNDERLAY_WAIT_MS       30000
#define UNDERLAY_POLL_MS       500

static int wait_for_wifi_ipv4(void)
{
	struct net_if *wifi = net_if_get_first_wifi();

	if (wifi == NULL) {
		LOG_ERR("no wifi iface");
		return -ENODEV;
	}
	for (int waited = 0; waited < UNDERLAY_WAIT_MS; waited += UNDERLAY_POLL_MS) {
		if (net_if_ipv4_get_global_addr(wifi, NET_ADDR_PREFERRED) != NULL) {
			LOG_INF("wifi IPv4 up after %d ms", waited);
			return 0;
		}
		k_sleep(K_MSEC(UNDERLAY_POLL_MS));
	}
	LOG_WRN("no wifi IPv4 after %d ms; proceeding", UNDERLAY_WAIT_MS);
	return -ETIMEDOUT;
}

static int parse_cidr(const char *str, struct net_sockaddr *out, uint8_t *mask_len)
{
	if (net_ipaddr_parse_mask(str, strlen(str), out, mask_len) == NULL) {
		LOG_ERR("parse_cidr(\"%s\") failed", str);
		return -EINVAL;
	}
	if (out->sa_family != NET_AF_INET) {
		LOG_ERR("only IPv4 supported in spike");
		return -EAFNOSUPPORT;
	}
	return 0;
}

static int set_private_key(struct net_if *vpn)
{
	struct virtual_interface_req_params params = {0};
	uint8_t key[NET_VIRTUAL_MAX_PUBLIC_KEY_LEN];
	size_t olen;
	int ret;

	ret = base64_decode(key, sizeof(key), &olen,
			    (const uint8_t *)LOCAL_PRIVATE_KEY_B64,
			    strlen(LOCAL_PRIVATE_KEY_B64));
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

static void log_local_public_key(struct net_if *vpn)
{
	struct virtual_interface_req_params params = {0};
	char b64[NET_VIRTUAL_MAX_PUBLIC_KEY_LEN * 2];
	size_t olen;

	if (net_mgmt(NET_REQUEST_VIRTUAL_INTERFACE_GET_PUBLIC_KEY,
		     vpn, &params, sizeof(params)) < 0) {
		return;
	}
	if (base64_encode(b64, sizeof(b64), &olen,
			  params.public_key.data, params.public_key.len) == 0) {
		LOG_INF("local public key: %s", b64);
	}
}

static int assign_local_addr(struct net_if *vpn)
{
	struct net_sockaddr_storage ss = {0};
	struct net_sockaddr *paddr = (struct net_sockaddr *)&ss;
	struct net_sockaddr_in mask_sa = {0};
	uint8_t mask_len = 0;
	int ret;

	ret = parse_cidr(LOCAL_TUNNEL_CIDR, paddr, &mask_len);
	if (ret < 0) {
		return ret;
	}
	if (net_if_ipv4_addr_add(vpn, &net_sin(paddr)->sin_addr,
				 NET_ADDR_MANUAL, 0) == NULL) {
		LOG_ERR("addr_add failed");
		return -ENOENT;
	}
	if (net_mask_len_to_netmask(NET_AF_INET, mask_len,
				    (struct net_sockaddr *)&mask_sa) < 0) {
		return -EINVAL;
	}
	(void)net_if_ipv4_set_netmask_by_addr(vpn, &net_sin(paddr)->sin_addr,
					      &mask_sa.sin_addr);
	return 0;
}

static int add_peer(void)
{
	struct wireguard_peer_config peer = {0};
	struct net_sockaddr_storage ss = {0};
	struct net_sockaddr *paddr = (struct net_sockaddr *)&ss;
	struct net_if *peer_iface = NULL;
	uint8_t mask_len = 0;
	int ret;

	peer.public_key = PEER_PUBLIC_KEY_B64;
	peer.keepalive_interval = KEEPALIVE_SECONDS;

	if (!net_ipaddr_parse(PEER_ENDPOINT, strlen(PEER_ENDPOINT), paddr) ||
	    paddr->sa_family != NET_AF_INET) {
		LOG_ERR("endpoint parse failed");
		return -EINVAL;
	}
	memcpy(&peer.endpoint_ip, paddr, sizeof(struct net_sockaddr_in));

	ret = parse_cidr(PEER_ALLOWED_CIDR, paddr, &mask_len);
	if (ret < 0) {
		return ret;
	}
	peer.allowed_ip[0].is_valid = true;
	peer.allowed_ip[0].mask_len = mask_len;
	peer.allowed_ip[0].addr.family = NET_AF_INET;
	memcpy(&peer.allowed_ip[0].addr.in_addr,
	       &net_sin(paddr)->sin_addr, sizeof(struct net_in_addr));

	ret = wireguard_peer_add(&peer, &peer_iface);
	if (ret < 0) {
		LOG_ERR("wireguard_peer_add failed (%d)", ret);
		return ret;
	}
	LOG_INF("wg peer id=%d iface=%d", ret,
		peer_iface ? net_if_get_by_iface(peer_iface) : -1);
	return 0;
}

static int send_hello(void)
{
	struct net_sockaddr_storage ss = {0};
	struct net_sockaddr *paddr = (struct net_sockaddr *)&ss;
	int sock, n;

	if (!net_ipaddr_parse(PEER_TUNNEL_ADDR, strlen(PEER_TUNNEL_ADDR), paddr) ||
	    paddr->sa_family != NET_AF_INET) {
		return -EINVAL;
	}
	net_sin(paddr)->sin_port = sys_cpu_to_be16(HELLO_PORT);

	sock = zsock_socket(NET_AF_INET, NET_SOCK_DGRAM, NET_IPPROTO_UDP);
	if (sock < 0) {
		LOG_ERR("socket: %d", errno);
		return -errno;
	}
	n = zsock_sendto(sock, HELLO_MSG, strlen(HELLO_MSG), 0, paddr,
			 sizeof(struct net_sockaddr_in));
	zsock_close(sock);
	if (n < 0) {
		LOG_ERR("sendto: %d", errno);
		return -errno;
	}
	LOG_INF("sent %d bytes to %s:%d", n, PEER_TUNNEL_ADDR, HELLO_PORT);
	return 0;
}

int tailscaleStart(void)
{
	struct net_if *vpn;
	int ret;

	(void)wait_for_wifi_ipv4();

	vpn = net_if_get_first_by_type(&NET_L2_GET_NAME(VIRTUAL));
	if (vpn == NULL) {
		LOG_ERR("no VPN iface (CONFIG_WIREGUARD?)");
		return -ENODEV;
	}
	net_virtual_set_name(vpn, "wg0");

	ret = set_private_key(vpn);
	if (ret < 0) {
		return ret;
	}
	log_local_public_key(vpn);

	ret = assign_local_addr(vpn);
	if (ret < 0) {
		return ret;
	}
	if (!net_if_is_up(vpn)) {
		(void)net_if_up(vpn);
	}

	ret = add_peer();
	if (ret < 0) {
		return ret;
	}
	return send_hello();
}
