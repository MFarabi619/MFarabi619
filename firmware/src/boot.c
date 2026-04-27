#include <zephyr/kernel.h>
#include "esp_wifi.h"
#include <esp_sleep.h>
// #include <zephyr/net/conn_mgr_connectivity.h>

// #if defined(CONFIG_NET_L2_PPP)
// #include <zephyr/net/ppp.h>
// struct net_if *get_ppp_iface(void) {
// 	return net_if_get_first_by_type(&NET_L2_GET_NAME(PPP));
// }
// #else
// struct net_if *get_ppp_iface(void) {
// 	return NULL;
// }
// #endif

/* Work around Zephyr ESP32 WiFi driver race in esp32_wifi_connect() */
void wifi_pre_start(void)
{
	esp_wifi_set_mode(ESP32_WIFI_MODE_STA);
	esp_wifi_start();
}

#define AWAKE_DURATION_MS   5000
#define SLEEP_DURATION_SEC  5

static void deep_sleep_handler(struct k_work *work)
{
	esp_sleep_enable_timer_wakeup(SLEEP_DURATION_SEC * 1000000ULL);
	printk("Entering deep sleep for %d seconds\n", SLEEP_DURATION_SEC);
	esp_deep_sleep_start();
}

K_WORK_DELAYABLE_DEFINE(deep_sleep_work, deep_sleep_handler);

void schedule_deep_sleep(void)
{
	// k_work_schedule(&deep_sleep_work, K_MSEC(AWAKE_DURATION_MS));
}
