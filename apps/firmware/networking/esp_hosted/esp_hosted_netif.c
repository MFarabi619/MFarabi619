#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/net_pkt.h>
#include <zephyr/net/ethernet.h>
#include <zephyr/net/wifi_mgmt.h>
#include <zephyr/net/wifi_nm.h>
#include <zephyr/net/net_mgmt.h>
#include <zephyr/net/net_event.h>
#include <zephyr/net/dhcpv4.h>
#include <zephyr/logging/log.h>
#include <string.h>
#include "esp_hosted.h"

LOG_MODULE_REGISTER(esp_hosted_netif, LOG_LEVEL_INF);

#define ESP_HOSTED_MAX_FRAME_LEN 1600

static struct {
	struct net_if *iface;
	uint8_t mac[6];
	enum wifi_iface_state state;
} esp_hosted_context;

static K_THREAD_STACK_DEFINE(event_stack, 8192);
static struct k_thread event_thread;

int esp_hosted_wifi_setup(void);
void esp_hosted_wifi_event_task(void *a, void *b, void *c);
int esp_hosted_wifi_connect(const uint8_t *ssid, uint16_t ssid_len,
			  const uint8_t *psk, uint16_t psk_len);
int esp_hosted_wifi_disconnect(void);
int esp_hosted_wifi_query_dhcp(void);

void esp_hosted_netif_set_mac(const uint8_t *mac)
{
	memcpy(esp_hosted_context.mac, mac, sizeof(esp_hosted_context.mac));
}

void esp_hosted_netif_recv(uint8_t if_type, const uint8_t *frame, uint16_t len)
{
	struct net_if *iface = esp_hosted_context.iface;
	struct net_pkt *pkt;

	ARG_UNUSED(if_type);
	if (len >= 38 && frame[12] == 0x08 && frame[13] == 0x00) {
		LOG_INF("rx ip4 proto=%u src=%u.%u.%u.%u dst=%u.%u.%u.%u dport=%u",
			frame[23], frame[26], frame[27], frame[28], frame[29],
			frame[30], frame[31], frame[32], frame[33],
			(frame[36] << 8) | frame[37]);
	}
	if (len >= 55 && frame[12] == 0x86 && frame[13] == 0xdd && frame[20] == 58) {
		LOG_INF("rx icmp6 type=%u", frame[54]);
	}
	if (!iface || !net_if_flag_is_set(iface, NET_IF_UP)) {
		return;
	}
	pkt = net_pkt_rx_alloc_with_buffer(iface, len, NET_AF_UNSPEC, 0, K_MSEC(200));
	if (!pkt) {
		return;
	}
	if (net_pkt_write(pkt, frame, len) < 0 || net_recv_data(iface, pkt) < 0) {
		net_pkt_unref(pkt);
	}
}

void esp_hosted_netif_connected(int status)
{
	esp_hosted_context.state = status ? WIFI_STATE_DISCONNECTED : WIFI_STATE_COMPLETED;
	if (status) {
		net_if_dormant_on(esp_hosted_context.iface);
	} else {
		net_if_dormant_off(esp_hosted_context.iface);
	}
	wifi_mgmt_raise_connect_result_event(esp_hosted_context.iface, status);
}

static void esp_hosted_autoconnect(struct k_work *work);
static K_WORK_DELAYABLE_DEFINE(autoconnect_work, esp_hosted_autoconnect);

#define AUTOCONNECT_RETRY_DELAY K_SECONDS(3)

void esp_hosted_netif_disconnected(int status)
{
	bool was_associating = esp_hosted_context.state == WIFI_STATE_ASSOCIATING;

	net_if_dormant_on(esp_hosted_context.iface);
	esp_hosted_context.state = WIFI_STATE_DISCONNECTED;
	if (was_associating) {
		wifi_mgmt_raise_connect_result_event(esp_hosted_context.iface, status);
	} else {
		wifi_mgmt_raise_disconnect_result_event(esp_hosted_context.iface, status);
	}
	k_work_schedule(&autoconnect_work, AUTOCONNECT_RETRY_DELAY);
}

static int esp_hosted_send(const struct device *dev, struct net_pkt *pkt)
{
	static uint8_t frame[ESP_HOSTED_MAX_FRAME_LEN];
	size_t len = net_pkt_get_len(pkt);

	ARG_UNUSED(dev);
	if (len > sizeof(frame)) {
		return -EMSGSIZE;
	}
	if (net_pkt_read(pkt, frame, len) < 0) {
		return -EIO;
	}
	if (len >= 14) {
		LOG_INF("tx eth type=%02x%02x dst=%02x:%02x:%02x:%02x:%02x:%02x len=%u",
			frame[12], frame[13], frame[0], frame[1], frame[2], frame[3],
			frame[4], frame[5], (unsigned int)len);
	}
	int tx_ret = esp_hosted_tx(ESP_STA_IF, 0, frame, len);

	if (tx_ret) {
		LOG_ERR("tx failed: %d", tx_ret);
	}
	return tx_ret;
}

static int esp_hosted_connect(const struct device *dev, struct net_if *iface,
			      struct wifi_connect_req_params *params)
{
	int ret;

	ARG_UNUSED(dev);
	ARG_UNUSED(iface);
	if (esp_hosted_context.state == WIFI_STATE_ASSOCIATING ||
	    esp_hosted_context.state == WIFI_STATE_COMPLETED) {
		return -EALREADY;
	}
	esp_hosted_context.state = WIFI_STATE_ASSOCIATING;
	ret = esp_hosted_wifi_connect(params->ssid, params->ssid_length,
				    params->psk, params->psk_length);
	if (ret) {
		esp_hosted_context.state = WIFI_STATE_DISCONNECTED;
	}
	return ret;
}

static int esp_hosted_disconnect(const struct device *dev, struct net_if *iface)
{
	ARG_UNUSED(dev);
	ARG_UNUSED(iface);
	return esp_hosted_wifi_disconnect();
}

static int esp_hosted_status(const struct device *dev, struct net_if *iface,
			     struct wifi_iface_status *status)
{
	ARG_UNUSED(dev);
	ARG_UNUSED(iface);
	status->state = esp_hosted_context.state;
	status->band = WIFI_FREQ_BAND_2_4_GHZ;
	status->iface_mode = WIFI_MODE_INFRA;
	status->link_mode = WIFI_LINK_MODE_UNKNOWN;
	return 0;
}

static const struct wifi_mgmt_ops esp_hosted_mgmt = {
	.connect = esp_hosted_connect,
	.disconnect = esp_hosted_disconnect,
	.iface_status = esp_hosted_status,
};

static void esp_hosted_iface_init(struct net_if *iface)
{
	esp_hosted_context.iface = iface;
	net_eth_set_if_type_wifi(iface);
	net_if_set_link_addr(iface, esp_hosted_context.mac, sizeof(esp_hosted_context.mac), NET_LINK_ETHERNET);
	ethernet_init(iface);
	net_if_dormant_on(iface);
	wifi_nm_register_mgd_type_iface(wifi_nm_get_instance("esp_hosted"), WIFI_TYPE_STA, iface);
}

static int esp_hosted_dev_init(const struct device *dev)
{
	ARG_UNUSED(dev);
	if (esp_hosted_transport_init()) {
		LOG_ERR("transport init failed");
		return -EIO;
	}
	if (esp_hosted_wifi_setup()) {
		LOG_ERR("wifi setup failed");
		return -EIO;
	}
	k_thread_create(&event_thread, event_stack, K_THREAD_STACK_SIZEOF(event_stack),
			esp_hosted_wifi_event_task, NULL, NULL, NULL, K_PRIO_COOP(7), 0, K_NO_WAIT);
	k_thread_name_set(&event_thread, "esp_hosted_rx");
	return 0;
}

static const struct net_wifi_mgmt_offload esp_hosted_api = {
	.wifi_iface.iface_api.init = esp_hosted_iface_init,
	.wifi_iface.send = esp_hosted_send,
	.wifi_mgmt_api = &esp_hosted_mgmt,
};

NET_DEVICE_INIT(esp_hosted, "sta_if", esp_hosted_dev_init, NULL, &esp_hosted_context, NULL,
		CONFIG_WIFI_INIT_PRIORITY, &esp_hosted_api, ETHERNET_L2,
		NET_L2_GET_CTX_TYPE(ETHERNET_L2), NET_ETH_MTU);

DEFINE_WIFI_NM_INSTANCE(esp_hosted, &esp_hosted_mgmt);

static void esp_hosted_dhcp_query(struct k_work *work)
{
	ARG_UNUSED(work);
	esp_hosted_wifi_query_dhcp();
}

static K_WORK_DELAYABLE_DEFINE(dhcp_query_work, esp_hosted_dhcp_query);

static void esp_hosted_dhcp_on_connect(uint64_t event, struct net_if *iface, void *info,
				       size_t info_len, void *user_data)
{
	const struct wifi_status *status = info;

	ARG_UNUSED(event);
	ARG_UNUSED(info_len);
	ARG_UNUSED(user_data);
	if (iface != esp_hosted_context.iface) {
		return;
	}
	if (status && status->status == 0) {
		k_work_schedule(&dhcp_query_work, K_SECONDS(2));
		net_dhcpv4_start(iface);
	}
}

static void esp_hosted_dhcp_on_disconnect(uint64_t event, struct net_if *iface, void *info,
					  size_t info_len, void *user_data)
{
	ARG_UNUSED(event);
	ARG_UNUSED(info);
	ARG_UNUSED(info_len);
	ARG_UNUSED(user_data);
	if (iface != esp_hosted_context.iface) {
		return;
	}
	net_dhcpv4_stop(iface);
}

NET_MGMT_REGISTER_EVENT_HANDLER(esp_hosted_dhcp_start, NET_EVENT_WIFI_CONNECT_RESULT,
			       esp_hosted_dhcp_on_connect, NULL);
NET_MGMT_REGISTER_EVENT_HANDLER(esp_hosted_dhcp_stop, NET_EVENT_WIFI_DISCONNECT_RESULT,
			       esp_hosted_dhcp_on_disconnect, NULL);

static void esp_hosted_autoconnect(struct k_work *work)
{
	ARG_UNUSED(work);
	if (esp_hosted_context.iface &&
	    esp_hosted_context.state != WIFI_STATE_ASSOCIATING &&
	    esp_hosted_context.state != WIFI_STATE_COMPLETED) {
		net_mgmt(NET_REQUEST_WIFI_CONNECT_STORED, esp_hosted_context.iface, NULL, 0);
	}
}

static int esp_hosted_autoconnect_submit(void)
{
	k_work_schedule(&autoconnect_work, K_NO_WAIT);
	return 0;
}

SYS_INIT(esp_hosted_autoconnect_submit, APPLICATION, 99);
