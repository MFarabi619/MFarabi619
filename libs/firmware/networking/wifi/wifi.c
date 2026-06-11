/*
 * Copyright (c) 2026 Apidae Systems
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Thin C glue exposing wifi_mgmt to Rust. NET_REQUEST_WIFI_*_*
 * are bit-packed macros that are safer to dereference in C than to
 * hardcode as Rust constants. STA and AP coexist on ESP32-S3 (same channel).
 */

#include <errno.h>
#include <stdbool.h>

#include <zephyr/net/dhcpv4_server.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/wifi_mgmt.h>

#include "route_ipv4.h"

int wifi_sta_connect_stored(void)
{
	struct net_if *iface = net_if_get_first_wifi();

	if (iface == NULL) {
		return -ENODEV;
	}
	return net_mgmt(NET_REQUEST_WIFI_CONNECT_STORED, iface, NULL, 0);
}

bool wifi_sta_has_ipv4(void)
{
	struct net_if *iface = net_if_get_first_wifi();

	if (iface == NULL) {
		return false;
	}
	return net_if_ipv4_get_global_addr(iface, NET_ADDR_PREFERRED) != NULL;
}

int wifi_sta_install_default_route(void)
{
	struct net_if *iface = net_if_get_first_wifi();

	if (iface == NULL) {
		return -ENODEV;
	}

	struct in_addr gw = net_if_ipv4_get_gw(iface);

	if (net_ipv4_is_addr_unspecified(&gw)) {
		return -EAGAIN;
	}

	struct in_addr default_dst = {0};

	if (net_route_ipv4_add(iface, &default_dst, 0, &gw,
			       NET_ROUTE_INFINITE_LIFETIME,
			       NET_ROUTE_PREFERENCE_MEDIUM) == NULL) {
		return -ENOMEM;
	}
	return 0;
}

int wifi_ap_enable(const char *ssid, size_t ssid_len, const char *psk, size_t psk_len)
{
	struct net_if *iface = net_if_get_wifi_sap();

	if (iface == NULL) {
		return -ENODEV;
	}

	struct wifi_connect_req_params params = {
		.ssid = (const uint8_t *)ssid,
		.ssid_length = ssid_len,
		.psk = (const uint8_t *)psk,
		.psk_length = psk_len,
		.security = WIFI_SECURITY_TYPE_PSK,
		.channel = WIFI_CHANNEL_ANY,
		.band = WIFI_FREQ_BAND_2_4_GHZ,
		.mfp = WIFI_MFP_OPTIONAL,
	};
	return net_mgmt(NET_REQUEST_WIFI_AP_ENABLE, iface, &params, sizeof(params));
}

int wifi_ap_disable(void)
{
	struct net_if *iface = net_if_get_wifi_sap();

	if (iface == NULL) {
		return -ENODEV;
	}
	return net_mgmt(NET_REQUEST_WIFI_AP_DISABLE, iface, NULL, 0);
}

int wifi_ap_dhcpv4_server_start(void)
{
	struct net_if *iface = net_if_get_wifi_sap();

	if (iface == NULL) {
		return -ENODEV;
	}

	struct in_addr ap_addr = {.s4_addr = {192, 168, 4, 1}};
	struct in_addr netmask = {.s4_addr = {255, 255, 255, 0}};
	struct in_addr pool_base = {.s4_addr = {192, 168, 4, 11}};

	net_if_ipv4_set_gw(iface, &ap_addr);
	net_if_ipv4_addr_add(iface, &ap_addr, NET_ADDR_MANUAL, 0);
	net_if_ipv4_set_netmask_by_addr(iface, &ap_addr, &netmask);
	return net_dhcpv4_server_start(iface, &pool_base);
}
