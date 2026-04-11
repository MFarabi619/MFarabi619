#include "wifi.h"
#include "../drivers/neopixel.h"

#include <Arduino.h>
#include <WiFi.h>
#include <DNSServer.h>
#include <Preferences.h>
#include <ESPmDNS.h>

static volatile bool connected = false;
static bool mdns_started = false;
static bool ap_active = false;
static DNSServer dns_server;

static const char wifi_ssid_slot[33] __attribute__((used, aligned(4))) =
  "@@WIFI_SSID@@";
static const char wifi_pass_slot[65] __attribute__((used, aligned(4))) =
  "@@WIFI_PASS@@";

static bool nvs_get_string(const char *key, char *buf, size_t len) {
  Preferences prefs;
  prefs.begin(CONFIG_WIFI_NVS_NAMESPACE, true);
  size_t n = prefs.getString(key, buf, len);
  prefs.end();
  return n > 0;
}

void wifi_setup(void) {
  static bool setup_done = false;
  if (setup_done) return;
  setup_done = true;

  WiFi.persistent(false);
  WiFi.setAutoReconnect(true);

  WiFi.onEvent([](arduino_event_id_t event, arduino_event_info_t info) {
    switch (event) {
      case ARDUINO_EVENT_WIFI_STA_CONNECTED:
        Serial.printf("[wifi] %s\n", WiFi.eventName(event));
        break;

      case ARDUINO_EVENT_WIFI_STA_DISCONNECTED:
        Serial.printf("[wifi] %s reason: %s\n",
                      WiFi.eventName(event),
                      WiFi.disconnectReasonName(
                          (wifi_err_reason_t)info.wifi_sta_disconnected.reason));
        neopixel_yellow();
        connected = false;
        break;

      case ARDUINO_EVENT_WIFI_STA_GOT_IP:
        Serial.printf("[wifi] %s %s\n", WiFi.eventName(event),
                      WiFi.localIP().toString().c_str());
        connected = true;
        neopixel_green();
        if (!mdns_started && MDNS.begin(CONFIG_HOSTNAME)) {
          MDNS.setInstanceName(CONFIG_HOSTNAME);
          MDNS.addService("ssh", "tcp", CONFIG_SSH_PORT);
          MDNS.addService("http", "tcp", CONFIG_HTTP_PORT);
          MDNS.addServiceTxt("http", "tcp", "path", "/");
          MDNS.addServiceTxt("http", "tcp", "fw", ESP.getSdkVersion());
          Serial.printf("[mdns] %s.local\n", CONFIG_HOSTNAME);
          mdns_started = true;
        }
        break;

      default:
        break;
    }
  });
}

bool wifi_connect(void) {
  connected = false;

  WiFi.persistent(false);
  WiFi.setAutoReconnect(true);

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

  int result = WiFi.waitForConnectResult(CONFIG_WIFI_TIMEOUT_MS);
  connected = (result == WL_CONNECTED);
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
  Preferences prefs;
  prefs.begin(CONFIG_WIFI_NVS_NAMESPACE, false);
  prefs.putString("ssid", ssid);
  prefs.putString("pass", password);
  prefs.end();
  Serial.printf("[wifi] credentials saved: ssid=%s\n", ssid);
}

bool wifi_is_connected(void) {
  return connected;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Access Point + Captive Portal
// ─────────────────────────────────────────────────────────────────────────────

void wifi_get_ap_ssid(char *buf, size_t len) {
  Preferences prefs;
  prefs.begin(CONFIG_WIFI_NVS_NAMESPACE, true);
  size_t n = prefs.getString("ap_ssid", buf, len);
  prefs.end();
  if (n == 0) {
    strncpy(buf, CONFIG_AP_SSID, len - 1);
    buf[len - 1] = '\0';
  }
}

void wifi_get_ap_password(char *buf, size_t len) {
  Preferences prefs;
  prefs.begin(CONFIG_WIFI_NVS_NAMESPACE, true);
  size_t n = prefs.getString("ap_pass", buf, len);
  prefs.end();
  if (n == 0) {
    strncpy(buf, CONFIG_AP_PASSWORD, len - 1);
    buf[len - 1] = '\0';
  }
}

void wifi_set_ap_config(const char *ssid, const char *password) {
  Preferences prefs;
  prefs.begin(CONFIG_WIFI_NVS_NAMESPACE, false);
  prefs.putString("ap_ssid", ssid);
  prefs.putString("ap_pass", password);
  prefs.end();
  Serial.printf("[wifi] AP config saved: ssid=%s\n", ssid);
}

bool wifi_get_ap_enabled(void) {
  Preferences prefs;
  prefs.begin(CONFIG_WIFI_NVS_NAMESPACE, true);
  bool enabled = prefs.getBool("ap_on", true);
  prefs.end();
  return enabled;
}

void wifi_set_ap_enabled(bool enabled) {
  Preferences prefs;
  prefs.begin(CONFIG_WIFI_NVS_NAMESPACE, false);
  prefs.putBool("ap_on", enabled);
  prefs.end();

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
  dns_server.start(53, "*", ap_ip);

  ap_active = true;
  Serial.printf("[wifi] AP started: %s (%s)\n",
                ap_ssid, ap_ip.toString().c_str());
}

void wifi_stop_ap(void) {
  if (!ap_active) return;

  dns_server.stop();
  WiFi.softAPdisconnect(true);

  if (connected) {
    WiFi.mode(WIFI_MODE_STA);
  }

  ap_active = false;
  Serial.println(F("[wifi] AP stopped"));
}

bool wifi_is_ap_active(void) {
  return ap_active;
}
