#include "commands.h"
#include "../../networking/wifi.h"
#include "../../services/network.h"
#include "../ssh/ssh_server.h"

#include <Arduino.h>
#include <microshell.h>

static void cmd_reboot(struct ush_object *self,
                       struct ush_file_descriptor const *file,
                       int argc, char *argv[]) {
  (void)file; (void)argc; (void)argv;
  ush_print(self, (char *)"rebooting...\r\n");
  delay(100);
  ESP.restart();
}

static void cmd_reset(struct ush_object *self,
                      struct ush_file_descriptor const *file,
                      int argc, char *argv[]) {
  (void)file; (void)argc; (void)argv;
  ush_reset(self);
}

static void cmd_wifi_set(struct ush_object *self,
                         struct ush_file_descriptor const *file,
                         int argc, char *argv[]) {
  (void)file;
  if (argc != 3) {
    ush_print(self, (char *)"usage: wifi-set <ssid> <password>\r\n");
    return;
  }
  wifi_set_credentials(argv[1], argv[2]);
  ush_print(self, (char *)"saved. reboot to connect.\r\n");
}

static void cmd_wifi_connect(struct ush_object *self,
                             struct ush_file_descriptor const *file,
                             int argc, char *argv[]) {
  (void)file; (void)argc; (void)argv;
  ush_print(self, (char *)"connecting...\r\n");
  if (wifi_connect()) {
    ush_print(self, (char *)"connected, starting services...\r\n");
    network_services_start();
  } else {
    ush_print(self, (char *)"failed\r\n");
  }
}

static void cmd_exit(struct ush_object *self,
                     struct ush_file_descriptor const *file,
                     int argc, char *argv[]) {
  (void)file; (void)argc; (void)argv;
  if (ssh_server_request_exit(self)) {
    ush_print(self, (char *)"logout\r\n");
  } else {
    ush_print(self, (char *)"no remote session to exit\r\n");
  }
}

static const struct ush_file_descriptor cmd_files[] = {
  { .name = "reboot",       .description = "reboot the device",
    .help = "usage: reboot\r\n",           .exec = cmd_reboot },
  { .name = "reset",        .description = "reset shell",
    .help = "usage: reset\r\n",            .exec = cmd_reset },
  { .name = "exit",         .description = "close current ssh session",
    .help = "usage: exit\r\n",             .exec = cmd_exit },
  { .name = "wifi-set",     .description = "save WiFi credentials to NVS",
    .help = "usage: wifi-set <ssid> <password>\r\n", .exec = cmd_wifi_set },
  { .name = "wifi-connect", .description = "connect to saved WiFi network",
    .help = "usage: wifi-connect\r\n",     .exec = cmd_wifi_connect },
};

static struct ush_node_object cmd;

void commands_register(struct ush_object *ush) {
  ush_commands_add(ush, &cmd, cmd_files,
                   sizeof(cmd_files) / sizeof(cmd_files[0]));
}
