#include "../shell.h"
#include "../../../networking/wifi.h"
#include "../../../networking/provisioning.h"

#include <Arduino.h>
#include <WiFi.h>
#include <microshell.h>
#include <Preferences.h>
#include <ESPmDNS.h>
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
  WiFi.setHostname(buf);
}

//------------------------------------------
//  /etc/config — read-only system info
//------------------------------------------
static size_t config_get_data(struct ush_object *self,
                              struct ush_file_descriptor const *file,
                              uint8_t **data) {
  (void)self; (void)file;
  static char buf[512];
  snprintf(buf, sizeof(buf),
           "platform = esp32s3\r\n"
           "cpu_freq = %luMHz\r\n"
           "flash_size = %luKB\r\n"
           "sketch_size = %luKB\r\n"
           "sketch_free = %luKB\r\n"
           "sdk = %s\r\n"
           "mac = %012llX\r\n",
           (unsigned long)(ESP.getCpuFreqMHz()),
           (unsigned long)(ESP.getFlashChipSize() / 1024),
           (unsigned long)(ESP.getSketchSize() / 1024),
           (unsigned long)(ESP.getFreeSketchSpace() / 1024),
           ESP.getSdkVersion(),
           ESP.getEfuseMac());
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
  static char buf[512];
  if (WiFi.isConnected()) {
    snprintf(buf, sizeof(buf),
             "ssid = %s\r\n"
             "bssid = %s\r\n"
             "channel = %d\r\n"
             "rssi = %d dBm\r\n"
             "ip = %s\r\n"
             "gateway = %s\r\n"
             "subnet = %s\r\n"
             "dns = %s\r\n"
             "mac = %s\r\n"
             "hostname = %s\r\n",
             WiFi.SSID().c_str(),
             WiFi.BSSIDstr().c_str(),
             WiFi.channel(),
             WiFi.RSSI(),
             WiFi.localIP().toString().c_str(),
             WiFi.gatewayIP().toString().c_str(),
             WiFi.subnetMask().toString().c_str(),
             WiFi.dnsIP().toString().c_str(),
              WiFi.macAddress().c_str(),
              WiFi.getHostname());
  } else if (wifi_is_ap_active()) {
    snprintf(buf, sizeof(buf),
             "status = access_point\r\n"
             "ap_ssid = %s\r\n"
             "ap_ip = %s\r\n"
             "ap_clients = %u\r\n"
             "ap_mac = %s\r\n"
             "ap_hostname = %s\r\n",
             WiFi.softAPSSID().c_str(),
             WiFi.softAPIP().toString().c_str(),
             WiFi.softAPgetStationNum(),
             WiFi.softAPmacAddress().c_str(),
             WiFi.softAPgetHostname());
  } else {
    snprintf(buf, sizeof(buf), "status = disconnected\r\n");
  }
  *data = (uint8_t *)buf;
  return strlen(buf);
}

static size_t provisioned_get_data(struct ush_object *self,
                                   struct ush_file_descriptor const *file,
                                   uint8_t **data) {
  (void)self; (void)file;
  static const char *yes = "true";
  static const char *no = "false";
  bool p = provisioning_is_provisioned();
  *data = (uint8_t *)(p ? yes : no);
  return p ? 4 : 5;
}

static size_t username_get_data(struct ush_object *self,
                                struct ush_file_descriptor const *file,
                                uint8_t **data) {
  (void)self; (void)file;
  static char buf[64];
  if (provisioning_get_username(buf, sizeof(buf))) {
    *data = (uint8_t *)buf;
    return strlen(buf);
  }
  *data = (uint8_t *)"";
  return 0;
}

static void username_set_data(struct ush_object *self,
                              struct ush_file_descriptor const *file,
                              uint8_t *data, size_t size) {
  (void)self; (void)file;
  char buf[64];
  size_t len = (size < sizeof(buf) - 1) ? size : sizeof(buf) - 1;
  memcpy(buf, data, len);
  buf[len] = '\0';
  while (len > 0 && (buf[len-1] == '\r' || buf[len-1] == '\n' || buf[len-1] == ' '))
    buf[--len] = '\0';
  Preferences prefs;
  prefs.begin(CONFIG_PROV_NVS_NAMESPACE, false);
  prefs.putString("username", buf);
  prefs.end();
}

static size_t device_name_get_data(struct ush_object *self,
                                   struct ush_file_descriptor const *file,
                                   uint8_t **data) {
  (void)self; (void)file;
  static char buf[64];
  if (provisioning_get_device_name(buf, sizeof(buf))) {
    *data = (uint8_t *)buf;
    return strlen(buf);
  }
  *data = (uint8_t *)CONFIG_HOSTNAME;
  return strlen(CONFIG_HOSTNAME);
}

static void device_name_set_data(struct ush_object *self,
                                 struct ush_file_descriptor const *file,
                                 uint8_t *data, size_t size) {
  (void)self; (void)file;
  char buf[64];
  size_t len = (size < sizeof(buf) - 1) ? size : sizeof(buf) - 1;
  memcpy(buf, data, len);
  buf[len] = '\0';
  while (len > 0 && (buf[len-1] == '\r' || buf[len-1] == '\n' || buf[len-1] == ' '))
    buf[--len] = '\0';
  Preferences prefs;
  prefs.begin(CONFIG_PROV_NVS_NAMESPACE, false);
  prefs.putString("device_name", buf);
  prefs.end();
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
  {
    .name = "provisioned",
    .description = "provisioning status",
    .help = NULL,
    .exec = NULL,
    .get_data = provisioned_get_data,
  },
  {
    .name = "username",
    .description = "provisioned username",
    .help = NULL,
    .exec = NULL,
    .get_data = username_get_data,
    .set_data = username_set_data,
  },
  {
    .name = "device_name",
    .description = "device name",
    .help = NULL,
    .exec = NULL,
    .get_data = device_name_get_data,
    .set_data = device_name_set_data,
  },
};

static struct ush_node_object etc;

void etc_mount(struct ush_object *ush) {
  ush_node_mount(ush, "/etc", &etc, etc_files,
                 sizeof(etc_files) / sizeof(etc_files[0]));
}
