#include <networking/wifi.h>
#include <programs/led.h>

#include <zephyr/kernel.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/net_mgmt.h>
#include <zephyr/net/wifi_mgmt.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(wifi);

#define RECONNECT_DELAY K_SECONDS(5)

static struct net_mgmt_event_callback wifi_cb;
static struct k_work_delayable reconnect_work;

static void reconnect_handler(struct k_work *work)
{
	ARG_UNUSED(work);
	net_mgmt(NET_REQUEST_WIFI_CONNECT_STORED, net_if_get_default(), NULL, 0);
}

static void wifi_event_handler(struct net_mgmt_event_callback *cb,
			       uint64_t mgmt_event, struct net_if *iface)
{
	ARG_UNUSED(cb);
	ARG_UNUSED(iface);

	switch (mgmt_event) {
	case NET_EVENT_WIFI_CONNECT_RESULT:
		LOG_INF("Connected");
		led_set(color_green);
		break;
	case NET_EVENT_WIFI_DISCONNECT_RESULT:
		LOG_INF("Disconnected, retrying in 5s");
		led_set(color_yellow);
		k_work_schedule(&reconnect_work, RECONNECT_DELAY);
		break;
	}
}

void wifi_init(void)
{
	k_work_init_delayable(&reconnect_work, reconnect_handler);

	net_mgmt_init_event_callback(&wifi_cb, wifi_event_handler,
				     NET_EVENT_WIFI_CONNECT_RESULT |
				     NET_EVENT_WIFI_DISCONNECT_RESULT);
	net_mgmt_add_event_callback(&wifi_cb);

	net_mgmt(NET_REQUEST_WIFI_CONNECT_STORED, net_if_get_default(), NULL, 0);
}
