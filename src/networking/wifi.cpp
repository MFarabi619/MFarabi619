#include "wifi.h"

#include <Arduino.h>
#include <WiFi.h>
#include <Preferences.h>
#include <ESPmDNS.h>
#include "esp_netif.h"

static volatile bool connected = false;
static bool mdns_started = false;

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
