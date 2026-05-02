#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/drivers/hwinfo.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/fs/fs.h>
#include <zephyr/logging/log.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/net_mgmt.h>
#include <zephyr/net/wifi.h>
#include <zephyr/net/wifi_mgmt.h>
#include <zephyr/settings/settings.h>
#include <zephyr/sys/sys_heap.h>
#include <zephyr/sys/util.h>

#include <stdint.h>
#include <string.h>

LOG_MODULE_REGISTER(diagnostics, LOG_LEVEL_INF);

extern struct k_heap _system_heap;

#define BOOT_COUNT_KEY "ceratina/boot_count"

static uint32_t persisted_boot_count;

static int boot_count_load_handler(const char *name, size_t len,
				    settings_read_cb read_cb, void *cb_arg)
{
	if (strcmp(name, "boot_count") == 0 && len == sizeof(persisted_boot_count)) {
		ssize_t bytes_read = read_cb(cb_arg, &persisted_boot_count,
					      sizeof(persisted_boot_count));
		if (bytes_read != sizeof(persisted_boot_count)) {
			persisted_boot_count = 0;
		}
	}
	return 0;
}

SETTINGS_STATIC_HANDLER_DEFINE(diagnostics_boot_count, "ceratina", NULL,
			        boot_count_load_handler, NULL, NULL);

uint32_t diagnostics_increment_boot_count(void)
{
	static bool already_incremented;

	if (already_incremented) {
		return persisted_boot_count;
	}

	if (settings_subsys_init() != 0) {
		LOG_WRN("settings_subsys_init failed");
	} else {
		settings_load_subtree("ceratina");
	}

	persisted_boot_count += 1;
	already_incremented = true;

	int result = settings_save_one(BOOT_COUNT_KEY, &persisted_boot_count,
				        sizeof(persisted_boot_count));
	if (result != 0) {
		LOG_WRN("boot_count save failed: %d", result);
	}
	return persisted_boot_count;
}

int diagnostics_get_reset_cause(char *out, size_t out_size)
{
	if (!out || out_size == 0) {
		return -EINVAL;
	}

	uint32_t cause = 0;

	if (hwinfo_get_reset_cause(&cause) != 0) {
		cause = 0;
	}
	hwinfo_clear_reset_cause();

	const char *label;

	if (cause & RESET_POR) {
		label = "power-on";
	} else if (cause & RESET_BROWNOUT) {
		label = "brownout";
	} else if (cause & RESET_WATCHDOG) {
		label = "watchdog";
	} else if (cause & RESET_CPU_LOCKUP) {
		label = "cpu-lockup";
	} else if (cause & RESET_TEMPERATURE) {
		label = "temperature";
	} else if (cause & RESET_LOW_POWER_WAKE) {
		label = "low-power-wake";
	} else if (cause & RESET_SECURITY) {
		label = "security";
	} else if (cause & RESET_PARITY) {
		label = "parity";
	} else if (cause & RESET_PLL) {
		label = "pll";
	} else if (cause & RESET_CLOCK) {
		label = "clock";
	} else if (cause & RESET_DEBUG) {
		label = "debug";
	} else if (cause & RESET_HARDWARE) {
		label = "hardware";
	} else if (cause & RESET_USER) {
		label = "user";
	} else if (cause & RESET_PIN) {
		label = "pin";
	} else if (cause & RESET_SOFTWARE) {
		label = "software";
	} else {
		label = "unknown";
	}

	strncpy(out, label, out_size);
	out[out_size - 1] = '\0';
	return 0;
}

uint32_t diagnostics_get_heap_min_free(void)
{
	struct sys_memory_stats stats;

	if (sys_heap_runtime_stats_get(&_system_heap.heap, &stats) != 0) {
		return 0;
	}
	size_t total = stats.allocated_bytes + stats.free_bytes;

	if (stats.max_allocated_bytes > total) {
		return 0;
	}
	return (uint32_t)(total - stats.max_allocated_bytes);
}

uint32_t diagnostics_get_heap_total(void)
{
	struct sys_memory_stats stats;

	if (sys_heap_runtime_stats_get(&_system_heap.heap, &stats) != 0) {
		return 0;
	}
	return (uint32_t)(stats.allocated_bytes + stats.free_bytes);
}

static int wifi_iface_status_query(struct wifi_iface_status *status)
{
	struct net_if *iface = net_if_get_wifi_sta();

	if (!iface) {
		iface = net_if_get_default();
	}
	if (!iface) {
		return -ENODEV;
	}
	return net_mgmt(NET_REQUEST_WIFI_IFACE_STATUS, iface, status,
			sizeof(*status));
}

int diagnostics_get_wifi_ssid(char *out, size_t out_size)
{
	struct wifi_iface_status status = {0};

	if (!out || out_size == 0) {
		return -EINVAL;
	}
	if (wifi_iface_status_query(&status) != 0) {
		out[0] = '\0';
		return -EIO;
	}

	size_t length = MIN((size_t)status.ssid_len, out_size - 1);

	memcpy(out, status.ssid, length);
	out[length] = '\0';
	return 0;
}

int diagnostics_get_wifi_bssid(char *out, size_t out_size)
{
	struct wifi_iface_status status = {0};

	if (!out || out_size < 18) {
		return -EINVAL;
	}
	if (wifi_iface_status_query(&status) != 0) {
		out[0] = '\0';
		return -EIO;
	}

	snprintk(out, out_size, "%02X:%02X:%02X:%02X:%02X:%02X",
		 status.bssid[0], status.bssid[1], status.bssid[2],
		 status.bssid[3], status.bssid[4], status.bssid[5]);
	return 0;
}

uint8_t diagnostics_get_wifi_channel(void)
{
	struct wifi_iface_status status = {0};

	if (wifi_iface_status_query(&status) != 0) {
		return 0;
	}
	return status.channel;
}

int diagnostics_get_wifi_link_mode_string(char *out, size_t out_size)
{
	struct wifi_iface_status status = {0};

	if (!out || out_size == 0) {
		return -EINVAL;
	}
	if (wifi_iface_status_query(&status) != 0) {
		out[0] = '\0';
		return -EIO;
	}

	const char *mode = wifi_link_mode_txt(status.link_mode);

	strncpy(out, mode, out_size);
	out[out_size - 1] = '\0';
	return 0;
}

#if DT_NODE_EXISTS(DT_ALIAS(temp0))

int32_t diagnostics_get_cpu_temperature_milli_c(void)
{
	const struct device *dev = DEVICE_DT_GET(DT_ALIAS(temp0));
	struct sensor_value value;

	if (!device_is_ready(dev)) {
		return INT32_MIN;
	}
	if (sensor_sample_fetch(dev) != 0) {
		return INT32_MIN;
	}
	if (sensor_channel_get(dev, SENSOR_CHAN_DIE_TEMP, &value) != 0) {
		return INT32_MIN;
	}

	return value.val1 * 1000 + value.val2 / 1000;
}

#else

int32_t diagnostics_get_cpu_temperature_milli_c(void)
{
	return INT32_MIN;
}

#endif

uint32_t diagnostics_get_storage_free_bytes(void)
{
	struct fs_statvfs stats;

	if (fs_statvfs("/sd:", &stats) == 0) {
		return (uint32_t)((uint64_t)stats.f_bfree * (uint64_t)stats.f_frsize);
	}
	return 0;
}
