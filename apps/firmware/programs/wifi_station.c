#include <zephyr/kernel.h>
#include <zephyr/net/net_event.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/net_mgmt.h>
#include <zephyr/net/wifi_mgmt.h>

#include "wifi_station.h"

#define ADDRESS_RECHECK_PERIOD_SECONDS 1

/* Bounded waits with a recheck: a DHCP bind between the check and the wait would
 * otherwise go unnoticed until the next rebind. */
void wifi_station_wait_for_ipv4_address(void) {
  struct net_if *station = net_if_get_wifi_sta();
  if (station == NULL) {
    return;
  }
  while (net_if_ipv4_get_global_addr(station, NET_ADDR_PREFERRED) == NULL) {
    uint64_t raised_event;
    net_mgmt_event_wait_on_iface(station, NET_EVENT_IPV4_DHCP_BOUND, &raised_event,
                                 NULL, NULL, K_SECONDS(ADDRESS_RECHECK_PERIOD_SECONDS));
  }
}

/* Modem-sleep batches packets at DTIM intervals; the resulting latency spikes
 * overrun the robot's 0.5 s command timeouts and chop the drive. */
void wifi_station_disable_power_save(void) {
  struct net_if *station = net_if_get_wifi_sta();
  if (station == NULL) {
    return;
  }
  struct wifi_ps_params params = {.enabled = WIFI_PS_DISABLED};
  int result = net_mgmt(NET_REQUEST_WIFI_PS, station, &params, sizeof(params));
  if (result < 0) {
    printk("wifi_station: power save off failed (%d)\n", result);
  }
}
