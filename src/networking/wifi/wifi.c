/*
 * Route-install shims: `net_route_ipv4_add` lives in private
 * subsys/net/ip/route_ipv4.h, not in zephyr-sys bindings. Everything else
 * that used to live here moved to wifi/mod.rs against zephyr::raw.
 */

#include <errno.h>

#include <zephyr/net/net_if.h>

#include "route_ipv4.h"

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

/* The kernel's route lookup uses longest-prefix-match across the WHOLE route
 * table, ignoring onlink subnet membership when a default route matches. So
 * with `0.0.0.0/0` installed via PPP, packets destined to the AP subnet (e.g.
 * DNAT'd replies to STAs) get routed out PPP instead of the AP iface. Install
 * an explicit /24 entry on the AP iface so longest-prefix wins.
 */
int wifi_ap_install_subnet_route(void)
{
	struct net_if *iface = net_if_get_wifi_sap();

	if (iface == NULL) {
		return -ENODEV;
	}

	struct in_addr gw = net_if_ipv4_get_gw(iface);

	if (net_ipv4_is_addr_unspecified(&gw)) {
		return -EAGAIN;
	}

	struct in_addr subnet = gw;

	subnet.s4_addr[3] = 0;

	if (net_route_ipv4_add(iface, &subnet, 24, NULL,
			       NET_ROUTE_INFINITE_LIFETIME,
			       NET_ROUTE_PREFERENCE_MEDIUM) == NULL) {
		return -ENOMEM;
	}
	return 0;
}
