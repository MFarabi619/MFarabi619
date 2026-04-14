#include "coreutils.h"

#include "../../networking/wifi.h"

namespace {

void exec(struct ush_object *self,
          struct ush_file_descriptor const *file,
          int argc, char *argv[]) {
  (void)file;
  (void)argv;
  if (argc != 1) {
    ush_print_status(self, USH_STATUS_ERROR_COMMAND_WRONG_ARGUMENTS);
    return;
  }

  NetworkStatusSnapshot snapshot = {};
  networking::wifi::accessSnapshot(&snapshot);

  if (snapshot.connected) {
    ush_printf(self,
               "ssid=%s\r\n"
               "bssid=%s\r\n"
               "channel=%ld\r\n"
               "rssi=%ld\r\n"
               "ip=%s\r\n"
               "gateway=%s\r\n"
               "subnet=%s\r\n"
               "dns=%s\r\n"
               "mac=%s\r\n"
               "hostname=%s\r\n",
               snapshot.ssid,
               snapshot.bssid,
               (long)snapshot.channel,
               (long)snapshot.rssi,
               snapshot.ip,
               snapshot.gateway,
               snapshot.subnet,
               snapshot.dns,
               snapshot.mac,
               snapshot.hostname);
    return;
  }

  if (snapshot.ap.active) {
    ush_printf(self,
               "mode=access_point\r\n"
               "ap_ssid=%s\r\n"
               "ap_ip=%s\r\n"
               "ap_clients=%u\r\n"
               "ap_mac=%s\r\n"
               "ap_hostname=%s\r\n",
               snapshot.ap.ssid,
               snapshot.ap.ip,
               snapshot.ap.clients,
               snapshot.ap.mac,
               snapshot.ap.hostname);
    return;
  }

  ush_print(self, (char *)"disconnected\r\n");
}

}

const struct ush_file_descriptor programs::coreutils::ifconfig::descriptor = {
  .name = "ifconfig",
  .description = "show network interface status",
  .help = "usage: ifconfig\r\n",
  .exec = exec,
};
