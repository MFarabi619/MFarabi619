#include "wifi.h"
#include "../drivers/neopixel.h"

#include <Arduino.h>
#include <WiFi.h>
#include <DNSServer.h>
#include <Preferences.h>
#include <ESPmDNS.h>
#include "esp_netif.h"

static volatile bool connected = false;
static bool mdns_started = false;
static bool ap_active = false;
static DNSServer dns_server;

// Sentinel slots for pre-flash credential embedding.
// The web app's flash panel finds these byte patterns in the .bin
// and overwrites them with user-provided SSID/password before flashing.
static const char wifi_ssid_slot[33] __attribute__((used, aligned(4))) =
  "@@WIFI_SSID@@";
static const char wifi_pass_slot[65] __attribute__((used, aligned(4))) =
  "@@WIFI_PASS@@";

static bool nvs_get_string(const char *key, char *buf, size_t len) {
  Preferences preferences;
  preferences.begin(CONFIG_WIFI_NVS_NAMESPACE, true);
  String val = preferences.getString(key, "");
  preferences.end();
  if (val.length() == 0) return false;
  strncpy(buf, val.c_str(), len - 1);
  buf[len - 1] = '\0';
  return true;
}

static void wifi_event_handler(void *arg, esp_event_base_t base, int32_t id,
                               void *event_data) {
  if (id == WIFI_EVENT_STA_CONNECTED) {
    Serial.println(F("[wifi] connected"));
  } else if (id == WIFI_EVENT_STA_DISCONNECTED) {
    Serial.println(F("[wifi] disconnected, reconnecting..."));
    neopixel_yellow();
    connected = false;
    char ssid[CONFIG_WIFI_SSID_IEEE_802_11_MAX_LENGTH + 1] = {0};
    char pass[CONFIG_WIFI_PASS_IEEE_802_11_MAX_LENGTH + 1] = {0};
    if (nvs_get_string("ssid", ssid, sizeof(ssid))) {
      nvs_get_string("pass", pass, sizeof(pass));
      WiFi.begin(ssid, pass);
    }
  } else if (id == IP_EVENT_STA_GOT_IP) {
    ip_event_got_ip_t *event = (ip_event_got_ip_t *)event_data;
    Serial.printf("[wifi] got ip: %s\n",
                  IPAddress(event->ip_info.ip.addr).toString().c_str());
    connected = true;
    neopixel_green();

    if (!mdns_started && MDNS.begin(CONFIG_HOSTNAME)) {
      MDNS.addService("ssh", "tcp", CONFIG_SSH_PORT);
      MDNS.addService("http", "tcp", CONFIG_HTTP_PORT);
      Serial.printf("[mdns] %s.local\n", CONFIG_HOSTNAME);
      mdns_started = true;
    }
  }
}

void wifi_setup(void) {
  static bool setup_done = false;
  if (setup_done) return;
  setup_done = true;

  esp_netif_init();
  esp_event_loop_create_default();
  esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID,
                                      wifi_event_handler, NULL, NULL);
  esp_event_handler_instance_register(IP_EVENT, ESP_EVENT_ANY_ID,
                                      wifi_event_handler, NULL, NULL);
}

bool wifi_connect(void) {
  connected = false;

  char ssid[CONFIG_WIFI_SSID_IEEE_802_11_MAX_LENGTH + 1] = {0};
  char pass[CONFIG_WIFI_PASS_IEEE_802_11_MAX_LENGTH + 1] = {0};

#if defined(CONFIG_WIFI_SSID) && defined(CONFIG_WIFI_PASS)
  if (strlen(CONFIG_WIFI_SSID) > 0) {
    wifi_set_credentials(CONFIG_WIFI_SSID, CONFIG_WIFI_PASS);
    Serial.printf("[wifi] credentials from build flags: %s\n", CONFIG_WIFI_SSID);
  } else
#endif
  if (wifi_ssid_slot[0] != '@' && wifi_ssid_slot[0] != '\0') {
    wifi_set_credentials(wifi_ssid_slot, wifi_pass_slot);
    Serial.printf("[wifi] credentials from embedded: %s\n", wifi_ssid_slot);
  }

  if (!wifi_get_ssid(ssid, sizeof(ssid)) || ssid[0] == '\0') {
    Serial.println(F("[wifi] no SSID configured"));
    return false;
  }
  wifi_get_password(pass, sizeof(pass));

  WiFi.disconnect(true);
  WiFi.mode(WIFI_MODE_STA);
  WiFi.setHostname(CONFIG_HOSTNAME);
  WiFi.begin(ssid, pass);

  uint32_t start = millis();
  while (!connected && (millis() - start) < CONFIG_WIFI_TIMEOUT_MS) {
    vTaskDelay(pdMS_TO_TICKS(CONFIG_WIFI_POLL_MS));
  }
  return connected;
}

bool wifi_get_ssid(char *buf, size_t len) {
  return nvs_get_string("ssid", buf, len);
}

bool wifi_get_password(char *buf, size_t len) {
  return nvs_get_string("pass", buf, len);
}

void wifi_set_credentials(const char *ssid, const char *password) {
  char current_ssid[CONFIG_WIFI_SSID_IEEE_802_11_MAX_LENGTH + 1] = {0};
  char current_pass[CONFIG_WIFI_PASS_IEEE_802_11_MAX_LENGTH + 1] = {0};
  if (wifi_get_ssid(current_ssid, sizeof(current_ssid)) &&
      wifi_get_password(current_pass, sizeof(current_pass)) &&
      strcmp(current_ssid, ssid) == 0 && strcmp(current_pass, password) == 0) {
    return;
  }
  Preferences preferences;
  preferences.begin(CONFIG_WIFI_NVS_NAMESPACE, false);
  preferences.putString("ssid", ssid);
  preferences.putString("pass", password);
  preferences.end();
  Serial.printf("[wifi] credentials saved: ssid=%s\n", ssid);
}

bool wifi_is_connected(void) {
  return connected;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Access Point + Captive Portal DNS
// ─────────────────────────────────────────────────────────────────────────────

void wifi_get_ap_ssid(char *buf, size_t len) {
  Preferences preferences;
  preferences.begin(CONFIG_WIFI_NVS_NAMESPACE, true);
  String val = preferences.getString("ap_ssid", CONFIG_AP_SSID);
  preferences.end();
  strncpy(buf, val.c_str(), len - 1);
  buf[len - 1] = '\0';
}

void wifi_get_ap_password(char *buf, size_t len) {
  Preferences preferences;
  preferences.begin(CONFIG_WIFI_NVS_NAMESPACE, true);
  String val = preferences.getString("ap_pass", CONFIG_AP_PASSWORD);
  preferences.end();
  strncpy(buf, val.c_str(), len - 1);
  buf[len - 1] = '\0';
}

void wifi_set_ap_config(const char *ssid, const char *password) {
  Preferences preferences;
  preferences.begin(CONFIG_WIFI_NVS_NAMESPACE, false);
  preferences.putString("ap_ssid", ssid);
  preferences.putString("ap_pass", password);
  preferences.end();
  Serial.printf("[wifi] AP config saved: ssid=%s\n", ssid);
}

bool wifi_get_ap_enabled(void) {
  Preferences preferences;
  preferences.begin(CONFIG_WIFI_NVS_NAMESPACE, true);
  bool enabled = preferences.getBool("ap_on", true);
  preferences.end();
  return enabled;
}

void wifi_set_ap_enabled(bool enabled) {
  Preferences preferences;
  preferences.begin(CONFIG_WIFI_NVS_NAMESPACE, false);
  preferences.putBool("ap_on", enabled);
  preferences.end();

  if (enabled && !ap_active) {
    wifi_start_ap();
  } else if (!enabled && ap_active) {
    wifi_stop_ap();
  }
}

void wifi_start_ap(void) {
  if (ap_active) return;

  char ap_ssid[33] = {0};
  char ap_pass[65] = {0};
  wifi_get_ap_ssid(ap_ssid, sizeof(ap_ssid));
  wifi_get_ap_password(ap_pass, sizeof(ap_pass));

  WiFi.mode(WIFI_AP_STA);

  IPAddress ap_ip(192, 168, 4, 1);
  IPAddress gateway(192, 168, 4, 1);
  IPAddress subnet(255, 255, 255, 0);
  WiFi.softAPConfig(ap_ip, gateway, subnet);
  WiFi.softAP(ap_ssid, ap_pass, CONFIG_AP_CHANNEL);

  dns_server.setErrorReplyCode(DNSReplyCode::NoError);
  if (dns_server.start(53, "*", ap_ip)) {
    Serial.printf("[wifi] captive DNS started on %s\n",
                  ap_ip.toString().c_str());
  }

  ap_active = true;
  Serial.printf("[wifi] AP started: %s (%s)\n",
                ap_ssid, ap_ip.toString().c_str());
}

void wifi_stop_ap(void) {
  if (!ap_active) return;

  dns_server.stop();
  WiFi.softAPdisconnect(true);

  // Stay in STA mode if connected, otherwise pure STA still
  if (connected) {
    WiFi.mode(WIFI_MODE_STA);
  }

  ap_active = false;
  Serial.println(F("[wifi] AP stopped"));
}

bool wifi_is_ap_active(void) {
  return ap_active;
}

void wifi_dns_service(void) {
  if (ap_active) {
    dns_server.processNextRequest();
  }
}
