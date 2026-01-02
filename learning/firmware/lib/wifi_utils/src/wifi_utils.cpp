#include "wifi_utils.h"

void begin_wifi() {
  Serial.println(CLR_BLUE_B "\n=== NETWORK BRING-UP ===" CLR_RESET);
  Serial.printf(CLR_YELLOW "[WiFi] Connecting to SSID: %s\n" CLR_RESET,
                NETWORK_SSID);

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);
  WiFi.begin(NETWORK_SSID, NETWORK_PSK);

  Serial.print(CLR_YELLOW "[WiFi] Connecting" CLR_RESET);

  uint32_t t0 = millis();

  while (WiFi.status() != WL_CONNECTED && millis() - t0 < 15000) {
    Serial.print(CLR_YELLOW "." CLR_RESET);
    delay(300);
  }

  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println(CLR_GREEN "[WiFi] Connected" CLR_RESET);
    Serial.printf(CLR_MAGENTA_B "[WiFi] IP: %s" CLR_RESET, WiFi.localIP());
  } else {
    Serial.println(CLR_RED "[WiFi] ERROR: connect timeout. Check 2.4GHz/WPA2 "
                           "and password." CLR_RESET);
  }

  if (MDNS.begin(MDNS_HOSTNAME)) {
    Serial.printf(CLR_GREEN "[mDNS] Responder started (%s.local)\n" CLR_RESET,
                  MDNS_HOSTNAME);
  } else {
    Serial.println(CLR_RED "[mDNS] ERROR: Failed to start responder" CLR_RESET);
  }
}
