/*
 * Tiny C shim for the one routing call that needs Zephyr's private
 * subsys/net/ip/route_ipv4.h header (net_route_ipv4_add).  Everything
 * else that used to live here moved to wifi/mod.rs against zephyr::raw.
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
