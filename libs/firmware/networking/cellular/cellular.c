/*
 * C glue exposing Zephyr's cellular driver API to Rust. The driver's enums
 * (cellular_modem_info_type, cellular_signal_type, cellular_registration_status)
 * live in <zephyr/drivers/cellular.h> which zephyr-sys doesn't bindgen, so each
 * field gets its own thunk and Rust never sees the underlying enum values.
 */

#include <errno.h>
#include <stddef.h>
#include <string.h>

#include <zephyr/device.h>
#include <zephyr/drivers/cellular.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/net/conn_mgr_monitor.h>
#include <zephyr/net/net_event.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/net_mgmt.h>
#include <zephyr/pm/device.h>
#include <zephyr/settings/settings.h>
#include <zephyr/shell/shell.h>
#include <zephyr/sys/util.h>

/* Espressif HAL — for gpio_hold_dis() used by modem_reset_release SYS_INIT. */
#include <driver/gpio.h>

LOG_MODULE_REGISTER(cellular_owner, LOG_LEVEL_INF);

static const struct device *modem_device(void)
{
	return DEVICE_DT_GET(DT_ALIAS(modem));
}

int cellular_access(int field, char *buf, size_t buf_len)
{
	return cellular_get_modem_info(modem_device(),
				       (enum cellular_modem_info_type)field, buf, buf_len);
}

extern void on_cellular_registration_status(int status);
extern void on_cellular_modem_info_changed(void);

static void cellular_event_handler(const struct device *dev, enum cellular_event event,
				   const void *payload, void *user_data)
{
	ARG_UNUSED(dev);
	ARG_UNUSED(user_data);

	switch (event) {
	case CELLULAR_EVENT_REGISTRATION_STATUS_CHANGED: {
		const struct cellular_evt_registration_status *reg = payload;

		on_cellular_registration_status((int)reg->status);
		break;
	}
	case CELLULAR_EVENT_MODEM_INFO_CHANGED:
		on_cellular_modem_info_changed();
		break;
	default:
		break;
	}
}

int cellular_initialize_callbacks(void)
{
	return cellular_set_callback(modem_device(),
				     CELLULAR_EVENT_REGISTRATION_STATUS_CHANGED |
					     CELLULAR_EVENT_MODEM_INFO_CHANGED,
				     cellular_event_handler, NULL);
}

static int modem_reset_release(void)
{
	gpio_hold_dis((gpio_num_t)DT_GPIO_PIN(DT_NODELABEL(modem), mdm_reset_gpios));
	return 0;
}
SYS_INIT(modem_reset_release, PRE_KERNEL_2, 0);

static struct net_if *ppp_iface_ref;

extern void on_cellular_l4_connected(void);
extern void on_cellular_l4_disconnected(void);
extern void on_cellular_dns_server_added(void);

static void on_l4_event(uint64_t event, struct net_if *iface, void *info, size_t info_length,
			void *user_data)
{
	ARG_UNUSED(info);
	ARG_UNUSED(info_length);
	ARG_UNUSED(user_data);

	if (event == NET_EVENT_DNS_SERVER_ADD) {
		on_cellular_dns_server_added();
		return;
	}
	if (iface != ppp_iface_ref) {
		return;
	}
	if (event == NET_EVENT_L4_CONNECTED) {
		on_cellular_l4_connected();
	} else if (event == NET_EVENT_L4_DISCONNECTED) {
		on_cellular_l4_disconnected();
	}
}

NET_MGMT_REGISTER_EVENT_HANDLER(cellular_l4_cb,
				NET_EVENT_L4_CONNECTED | NET_EVENT_L4_DISCONNECTED |
					NET_EVENT_DNS_SERVER_ADD,
				on_l4_event, NULL);

#define CELLULAR_APN_MAX 64

static char persisted_apn[CELLULAR_APN_MAX];

static int apn_settings_set(const char *name, size_t len, settings_read_cb read_cb, void *cb_arg)
{
	const char *next;

	if (settings_name_steq(name, "apn", &next) && next == NULL) {
		ssize_t bytes_read = read_cb(cb_arg, persisted_apn,
					     MIN(len, sizeof(persisted_apn) - 1));
		if (bytes_read >= 0) {
			persisted_apn[bytes_read] = '\0';
		}
		return 0;
	}
	return -ENOENT;
}

SETTINGS_STATIC_HANDLER_DEFINE(cellular_apn, "cellular", NULL, apn_settings_set, NULL, NULL);

static int apn_load_into_modem(void)
{
	if (persisted_apn[0] == '\0') {
		return 0;
	}
	int rc = cellular_set_apn(modem_device(), persisted_apn);

	if (rc == 0) {
		LOG_INF("apn loaded: %s", persisted_apn);
	} else {
		LOG_WRN("apn load failed: %d", rc);
	}
	return rc;
}

int cellular_save_apn(const char *apn, size_t len)
{
	if (len >= sizeof(persisted_apn)) {
		return -EINVAL;
	}
	memcpy(persisted_apn, apn, len);
	persisted_apn[len] = '\0';
	return settings_save_one("cellular/apn", persisted_apn, strlen(persisted_apn));
}

int cellular_initialize(void)
{
	const struct device *modem = modem_device();

	if (!device_is_ready(modem)) {
		LOG_ERR("modem device not ready");
		return -ENODEV;
	}

	ppp_iface_ref = net_if_get_first_by_type(&NET_L2_GET_NAME(PPP));
	if (ppp_iface_ref == NULL) {
		LOG_ERR("No PPP interface found");
		return -ENODEV;
	}

	apn_load_into_modem();

	LOG_DBG("Powering on modem");
	pm_device_action_run(modem, PM_DEVICE_ACTION_RESUME);

	LOG_DBG("Bringing up PPP iface");
	int ret = net_if_up(ppp_iface_ref);

	if (ret < 0) {
		LOG_ERR("net_if_up failed: %d", ret);
		return ret;
	}

	return 0;
}

static int cmd_cellular_apn(const struct shell *sh, size_t argc, char **argv)
{
	if (argc < 2) {
		shell_print(sh, "usage: cellular apn <name>");
		return -EINVAL;
	}
	int rc = cellular_set_apn(modem_device(), argv[1]);

	if (rc != 0) {
		shell_print(sh, "set_apn failed: %d", rc);
		return rc;
	}
	int save_rc = cellular_save_apn(argv[1], strlen(argv[1]));

	if (save_rc < 0) {
		shell_warn(sh, "apn set but save failed: %d", save_rc);
	} else {
		shell_print(sh, "apn set to '%s' (persisted)", argv[1]);
	}
	return 0;
}

SHELL_STATIC_SUBCMD_SET_CREATE(cellular_subcmds,
	SHELL_CMD(apn, NULL, "Set APN: cellular apn <name>", cmd_cellular_apn),
	SHELL_SUBCMD_SET_END);

SHELL_CMD_REGISTER(cellular, &cellular_subcmds, "Cellular runtime", NULL);

struct net_if *cellular_ppp_iface(void)
{
	return ppp_iface_ref;
}
