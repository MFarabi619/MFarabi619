#include "../shell.h"
#include "../../../networking/wifi.h"

#include <Arduino.h>
#include <WiFi.h>
#include <microshell.h>
#include <string.h>

//------------------------------------------
//  /etc/hostname — read/write
//------------------------------------------
static size_t hostname_get_data(struct ush_object *self,
                                struct ush_file_descriptor const *file,
                                uint8_t **data) {
  (void)self; (void)file;
  *data = (uint8_t *)shell_get_hostname();
  return strlen((char *)*data);
}

static void hostname_set_data(struct ush_object *self,
                              struct ush_file_descriptor const *file,
                              uint8_t *data, size_t size) {
  (void)self; (void)file;
  char buf[CONFIG_SHELL_HOSTNAME_SIZE + 1];
  size_t len = (size < CONFIG_SHELL_HOSTNAME_SIZE) ? size : CONFIG_SHELL_HOSTNAME_SIZE;
  memcpy(buf, data, len);
  buf[len] = '\0';
  while (len > 0 && (buf[len-1] == '\r' || buf[len-1] == '\n' || buf[len-1] == ' '))
    buf[--len] = '\0';
  shell_set_hostname(buf);
}

//------------------------------------------
//  /etc/config — read-only system info
//------------------------------------------
static size_t config_get_data(struct ush_object *self,
                              struct ush_file_descriptor const *file,
                              uint8_t **data) {
  (void)self; (void)file;
  static char buf[256];
  snprintf(buf, sizeof(buf),
           "# microvisor system configuration\r\n"
           "platform = esp32s3\r\n"
           "cpu_freq = %luMHz\r\n"
           "flash_size = %luKB\r\n"
           "sdk = %s\r\n",
           (unsigned long)(ESP.getCpuFreqMHz()),
           (unsigned long)(ESP.getFlashChipSize() / 1024),
           ESP.getSdkVersion());
  *data = (uint8_t *)buf;
  return strlen(buf);
}

//------------------------------------------
//  /etc/wifi — read-only wifi status
//------------------------------------------
static size_t wifi_get_data(struct ush_object *self,
                            struct ush_file_descriptor const *file,
                            uint8_t **data) {
  (void)self; (void)file;
  static char buf[256];
  if (WiFi.isConnected()) {
    snprintf(buf, sizeof(buf),
             "ssid = %s\r\n"
             "ip = %s\r\n"
             "rssi = %d dBm\r\n"
             "mac = %s\r\n",
             WiFi.SSID().c_str(),
             WiFi.localIP().toString().c_str(),
             WiFi.RSSI(),
             WiFi.macAddress().c_str());
  } else {
    snprintf(buf, sizeof(buf), "status = disconnected\r\n");
  }
  *data = (uint8_t *)buf;
  return strlen(buf);
}

static const struct ush_file_descriptor etc_files[] = {
  {
    .name = "hostname",
    .description = "shell hostname",
    .help = NULL,
    .exec = NULL,
    .get_data = hostname_get_data,
    .set_data = hostname_set_data,
  },
  {
    .name = "config",
    .description = "system configuration",
    .help = NULL,
    .exec = NULL,
    .get_data = config_get_data,
  },
  {
    .name = "wifi",
    .description = "wifi status / credentials (write ssid:password)",
    .help = "read: show wifi status\r\nwrite: echo ssid:password > /etc/wifi\r\n",
    .exec = NULL,
    .get_data = wifi_get_data,
    .set_data = [](struct ush_object *self, struct ush_file_descriptor const *file,
                   uint8_t *data, size_t size) {
      (void)self; (void)file;
      // Parse "ssid:password" format
      char buf[128];
      size_t len = (size < sizeof(buf) - 1) ? size : sizeof(buf) - 1;
      memcpy(buf, data, len);
      buf[len] = '\0';
      // Strip trailing whitespace/newlines
      while (len > 0 && (buf[len-1] == '\r' || buf[len-1] == '\n' || buf[len-1] == ' '))
        buf[--len] = '\0';
      char *colon = strchr(buf, ':');
      if (!colon) return;
      *colon = '\0';
      wifi_set_credentials(buf, colon + 1);
    },
  },
  {
    .name = "user",
    .description = "current user",
    .help = NULL,
    .exec = NULL,
    .get_data = [](struct ush_object *self,
                   struct ush_file_descriptor const *file,
                   uint8_t **data) -> size_t {
      (void)self; (void)file;
      static const char *user = CONFIG_SSH_USER;
      *data = (uint8_t *)user;
      return strlen(user);
    },
  },
};

static struct ush_node_object etc;

void etc_mount(struct ush_object *ush) {
  ush_node_mount(ush, "/etc", &etc, etc_files,
                 sizeof(etc_files) / sizeof(etc_files[0]));
}
