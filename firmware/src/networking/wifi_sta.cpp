#include "wifi_internal.h"

#include "../programs/led.h"
#include "../services/identity.h"

#include <Arduino.h>
#include <ESPmDNS.h>
#include <WiFi.h>
#include <ColorFormat.h>

void networking::wifi::internal::configureMdnsServices(const char *hostname) {
  MDNS.setInstanceName(hostname);
  MDNS.addService("ssh", "tcp", config::ssh::PORT);
  MDNS.addService("http", "tcp", config::http::PORT);
  MDNS.addServiceTxt("http", "tcp", "path", "/");
  MDNS.addServiceTxt("http", "tcp", "fw", ESP.getSdkVersion());
}

void networking::wifi::sta::initialize() {
  static bool setup_done = false;
  if (setup_done) return;
  setup_done = true;

  WiFi.setAutoReconnect(true);
  WiFi.mode(WIFI_MODE_STA);

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
        LED.set(RGB_YELLOW);
        break;

      case ARDUINO_EVENT_WIFI_STA_GOT_IP:
        Serial.printf("[wifi] %s %s\n", WiFi.eventName(event),
                      WiFi.localIP().toString().c_str());
        LED.set(RGB_GREEN);
        if (!networking::wifi::internal::mdns_started && MDNS.begin(services::identity::accessHostname())) {
          networking::wifi::internal::configureMdnsServices(services::identity::accessHostname());
          Serial.printf("[mdns] %s.local\n", services::identity::accessHostname());
          networking::wifi::internal::mdns_started = true;
        }
        break;

      default:
        break;
    }
  });
}

void networking::wifi::configureHostname(const char *hostname) {
  if (!hostname || hostname[0] == '\0') return;

  WiFi.setHostname(hostname);

  if (networking::wifi::internal::mdns_started) {
    MDNS.end();
    networking::wifi::internal::mdns_started = false;
  }

  if (WiFi.isConnected() && MDNS.begin(hostname)) {
    networking::wifi::internal::configureMdnsServices(hostname);
    networking::wifi::internal::mdns_started = true;
  }
}

bool networking::wifi::sta::connect() {
  WifiConnectCommand command = {
    .request = {
      .ssid = nullptr,
      .password = nullptr,
      .enable_ap_fallback = false,
    },
    .result = {},
  };
  return networking::wifi::connect(&command);
}
