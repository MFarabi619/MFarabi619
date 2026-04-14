#include "coreutils.h"
#include "../../networking/wifi.h"

#include <stdio.h>

int programs::coreutils::cmd_ifconfig(int argc, char **argv) {
  (void)argv;
  if (argc != 1) { printf("usage: ifconfig\n"); return 1; }

  NetworkStatusSnapshot snapshot = {};
  networking::wifi::accessSnapshot(&snapshot);

  if (snapshot.connected) {
    printf("ssid=%s\n"
           "bssid=%s\n"
           "channel=%ld\n"
           "rssi=%ld\n"
           "ip=%s\n"
           "gateway=%s\n"
           "subnet=%s\n"
           "dns=%s\n"
           "mac=%s\n"
           "hostname=%s\n",
           snapshot.ssid, snapshot.bssid,
           (long)snapshot.channel, (long)snapshot.rssi,
           snapshot.ip, snapshot.gateway, snapshot.subnet,
           snapshot.dns, snapshot.mac, snapshot.hostname);
    return 0;
  }

  if (snapshot.ap.active) {
    printf("mode=access_point\n"
           "ap_ssid=%s\n"
           "ap_ip=%s\n"
           "ap_clients=%u\n"
           "ap_mac=%s\n"
           "ap_hostname=%s\n",
           snapshot.ap.ssid, snapshot.ap.ip, snapshot.ap.clients,
           snapshot.ap.mac, snapshot.ap.hostname);
    return 0;
  }

  printf("disconnected\n");
  return 0;
}
