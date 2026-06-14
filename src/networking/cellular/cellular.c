/*
 * Minimal C shim for the cellular driver. Two things live here that
 * zephyr-sys can't expose to Rust:
 *
 *   1. `cellular_modem_device` resolves DT_ALIAS(modem) — a preprocessor
 *      macro that has to run in C.
 *   2. `cellular_access` dispatches `cellular_get_modem_info`, which is a
 *      `static inline` going through DEVICE_API_GET(cellular, dev).
 *
 * Plus a SYS_INIT to release the modem reset GPIO hold on cold boot
 * (uses DT_GPIO_PIN macro + ESP-IDF gpio_hold_dis), and 3 const u64
 * exports so Rust can build its net_mgmt event-mask without replicating
 * Zephyr's bit-packing layout.
 */

#include <errno.h>
#include <stddef.h>

#include <zephyr/device.h>
#include <zephyr/drivers/cellular.h>
#include <zephyr/init.h>
#include <zephyr/net/net_event.h>
#include <zephyr/net/net_if.h>
#include <zephyr/sys/util.h>

#include "route_ipv4.h"

/* Espressif HAL — for gpio_hold_dis() used by modem_reset_release SYS_INIT. */
#include <driver/gpio.h>

extern struct net_if *cellular_ppp_iface(void);

const struct device *cellular_modem_device(void)
{
	return DEVICE_DT_GET(DT_ALIAS(modem));
}

int cellular_access(int field, char *buf, size_t buf_len)
{
	return cellular_get_modem_info(cellular_modem_device(),
				       (enum cellular_modem_info_type)field, buf, buf_len);
}

const uint64_t CELLULAR_NET_EVENT_L4_CONNECTED    = NET_EVENT_L4_CONNECTED;
const uint64_t CELLULAR_NET_EVENT_L4_DISCONNECTED = NET_EVENT_L4_DISCONNECTED;
const uint64_t CELLULAR_NET_EVENT_DNS_SERVER_ADD  = NET_EVENT_DNS_SERVER_ADD;

static int modem_reset_release(void)
{
	gpio_hold_dis((gpio_num_t)DT_GPIO_PIN(DT_NODELABEL(modem), mdm_reset_gpios));
	return 0;
}
SYS_INIT(modem_reset_release, PRE_KERNEL_2, 0);

/* Without a route table entry, the kernel's `ipv4_route_packet` drops
 * NAT-forwarded transit packets (no on-link match for arbitrary internet
 * destinations). PPP has no nexthop IP, so pass NULL for an on-link
 * default route via the PPP iface.
 */
int cellular_install_default_route(void)
{
	struct net_if *iface = cellular_ppp_iface();

	if (iface == NULL) {
		return -ENODEV;
	}

	struct in_addr default_dst = {0};

	if (net_route_ipv4_add(iface, &default_dst, 0, NULL,
			       NET_ROUTE_INFINITE_LIFETIME,
			       NET_ROUTE_PREFERENCE_MEDIUM) == NULL) {
		return -ENOMEM;
	}
	return 0;
}
