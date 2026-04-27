#include <zephyr/net/conn_mgr_connectivity_impl.h>
#include <zephyr/net/conn_mgr/connectivity_wifi_mgmt.h>
#include <zephyr/net/wifi_mgmt.h>
#include <zephyr/net/net_if.h>

static int wifi_mgmt_connect(struct conn_mgr_conn_binding *const binding)
{
	return net_mgmt(NET_REQUEST_WIFI_CONNECT_STORED,
			binding->iface, NULL, 0);
}

static int wifi_mgmt_disconnect(struct conn_mgr_conn_binding *const binding)
{
	return net_mgmt(NET_REQUEST_WIFI_DISCONNECT,
			binding->iface, NULL, 0);
}

static struct conn_mgr_conn_api wifi_mgmt_api = {
	.connect = wifi_mgmt_connect,
	.disconnect = wifi_mgmt_disconnect,
};

CONN_MGR_CONN_DEFINE(CONNECTIVITY_WIFI_MGMT, &wifi_mgmt_api);
