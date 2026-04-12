#include "../shell.h"
#include "../../../networking/wifi.h"
#include "../../../boot/provisioning.h"
#include "../../../services/identity.h"
#include "../../../services/system.h"

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
  *data = (uint8_t *)services::identity::accessHostname();
  return strlen((char *)*data);
}

static void hostname_set_data(struct ush_object *self,
                              struct ush_file_descriptor const *file,
                              uint8_t *data, size_t size) {
  (void)self; (void)file;
  char buf[config::shell::HOSTNAME_SIZE + 1];
  size_t len = (size < config::shell::HOSTNAME_SIZE) ? size : config::shell::HOSTNAME_SIZE;
  memcpy(buf, data, len);
  buf[len] = '\0';
  while (len > 0 && (buf[len-1] == '\r' || buf[len-1] == '\n' || buf[len-1] == ' '))
    buf[--len] = '\0';
  services::identity::configureHostname(buf);
}

//------------------------------------------
//  /etc/config — read-only system info
//------------------------------------------
static size_t config_get_data(struct ush_object *self,
                              struct ush_file_descriptor const *file,
                              uint8_t **data) {
  (void)self; (void)file;
  static char buf[640];
  SystemQuery query = {
    .preferred_storage = StorageKind::LittleFS,
    .snapshot = {},
  };
  services::system::accessSnapshot(&query);
  snprintf(buf, sizeof(buf),
           "chip = %s\r\n"
           "cores = %u\r\n"
           "revision = %u\r\n"
           "cpu_freq = %luMHz\r\n"
           "flash_size = %luMB\r\n"
           "flash_speed = %luMHz\r\n"
           "sketch_size = %luKB\r\n"
           "sketch_free = %luKB\r\n"
           "sdk = %s\r\n"
           "idf = %s\r\n"
           "arduino = %s\r\n"
           "mac = %012llX\r\n",
           query.snapshot.chip_model,
           query.snapshot.chip_cores,
           (unsigned)query.snapshot.chip_revision,
           (unsigned long)query.snapshot.cpu_mhz,
           (unsigned long)(query.snapshot.flash_size / (1024 * 1024)),
           (unsigned long)query.snapshot.flash_speed_mhz,
           (unsigned long)(query.snapshot.sketch_size / 1024),
           (unsigned long)(query.snapshot.sketch_free / 1024),
           query.snapshot.sdk_version,
           query.snapshot.idf_version,
           query.snapshot.arduino_version,
           ESP.getEfuseMac());
  *data = (uint8_t *)buf;
  return strlen(buf);
}

//------------------------------------------
//  /etc/temperature — chip temperature
//------------------------------------------
static size_t temperature_get_data(struct ush_object *self,
                                   struct ush_file_descriptor const *file,
                                   uint8_t **data) {
  (void)self; (void)file;
  static char buf[16];
  SystemQuery query = {
    .preferred_storage = StorageKind::LittleFS,
    .snapshot = {},
  };
  services::system::accessSnapshot(&query);
  snprintf(buf, sizeof(buf), "%.1f\r\n", query.snapshot.chip_temperature_celsius);
  *data = (uint8_t *)buf;
  return strlen(buf);
}

//------------------------------------------
//  /etc/firmware — sketch MD5 + version
//------------------------------------------
static size_t firmware_get_data(struct ush_object *self,
                                struct ush_file_descriptor const *file,
                                uint8_t **data) {
  (void)self; (void)file;
  static char buf[128];
  SystemQuery query = {
    .preferred_storage = StorageKind::LittleFS,
    .snapshot = {},
  };
  services::system::accessSnapshot(&query);
  snprintf(buf, sizeof(buf),
           "md5 = %s\r\n"
           "size = %luKB\r\n"
           "free = %luKB\r\n",
           query.snapshot.sketch_md5,
           (unsigned long)(query.snapshot.sketch_size / 1024),
           (unsigned long)(query.snapshot.sketch_free / 1024));
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
  NetworkStatusSnapshot snapshot = {};
  networking::wifi::accessSnapshot(&snapshot);
  WifiSavedConfig saved = {};
  networking::wifi::accessConfig(&saved);
  if (snapshot.connected) {
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
             snapshot.ssid,
             snapshot.bssid,
             snapshot.channel,
             snapshot.rssi,
             snapshot.ip,
             snapshot.gateway,
             snapshot.subnet,
             snapshot.dns,
             snapshot.mac,
             snapshot.hostname);
  } else if (snapshot.ap.active) {
    snprintf(buf, sizeof(buf),
             "status = access_point\r\n"
             "ap_ssid = %s\r\n"
             "ap_ip = %s\r\n"
             "ap_clients = %u\r\n"
             "ap_mac = %s\r\n"
             "ap_hostname = %s\r\n",
             snapshot.ap.ssid,
             snapshot.ap.ip,
             snapshot.ap.clients,
             snapshot.ap.mac,
             snapshot.ap.hostname);
  } else if (saved.valid) {
    snprintf(buf, sizeof(buf),
             "status = disconnected\r\n"
             "saved_ssid = %s\r\n"
             "saved_password = %s\r\n",
             saved.ssid,
             saved.password);
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
  bool p = boot::provisioning::isProvisioned();
  *data = (uint8_t *)(p ? yes : no);
  return p ? 4 : 5;
}

static size_t username_get_data(struct ush_object *self,
                                struct ush_file_descriptor const *file,
                                uint8_t **data) {
  (void)self; (void)file;
  static char buf[64];
  IdentityStringQuery query = {
    .buffer = buf,
    .capacity = sizeof(buf),
    .ok = false,
  };
  if (services::identity::accessUsername(&query)) {
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
  services::identity::configureUsername(buf);
}

static size_t device_name_get_data(struct ush_object *self,
                                   struct ush_file_descriptor const *file,
                                   uint8_t **data) {
  (void)self; (void)file;
  static char buf[64];
  IdentityStringQuery query = {
    .buffer = buf,
    .capacity = sizeof(buf),
    .ok = false,
  };
  if (services::identity::accessDeviceName(&query)) {
    *data = (uint8_t *)buf;
    return strlen(buf);
  }
  *data = (uint8_t *)config::HOSTNAME;
  return strlen(config::HOSTNAME);
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
  services::identity::configureDeviceName(buf);
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
     .description = "wifi status / saved credentials",
     .help = "read: show wifi status and saved config\r\nwrite: echo ssid:password > /etc/wifi (save only)\r\n",
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
      WifiSavedConfig config = {};
      strlcpy(config.ssid, buf, sizeof(config.ssid));
      strlcpy(config.password, colon + 1, sizeof(config.password));
      networking::wifi::storeConfig(&config);
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
  {
    .name = "temperature",
    .description = "chip temperature (celsius)",
    .help = NULL,
    .exec = NULL,
    .get_data = temperature_get_data,
  },
  {
    .name = "firmware",
    .description = "firmware MD5, size, free OTA space",
    .help = NULL,
    .exec = NULL,
    .get_data = firmware_get_data,
  },
};

static struct ush_node_object etc;

void etc_mount(struct ush_object *ush) {
  ush_node_mount(ush, "/etc", &etc, etc_files,
                 sizeof(etc_files) / sizeof(etc_files[0]));
}
