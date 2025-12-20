#include "setup.h"

const char *MDNS_HOSTNAME = "microvisor";

AsyncWebServer server(80);

#if CONFIG_FREERTOS_UNICORE
static const BaseType_t app_cpu = 0;
#else
static const BaseType_t app_cpu = 1;
#endif

void setup() {
  pinMode(REQUEST_INDICATOR_LED_PIN, OUTPUT);
  digitalWrite(REQUEST_INDICATOR_LED_PIN, LOW);
  Serial.begin(MONITOR_SPEED);
  delay(200);

  Serial.println(CLR_BLUE_B "\n=== BOOT SEQUENCE ===" CLR_RESET);
  Serial.println(CLR_YELLOW "[Logger] Initializing..." CLR_RESET);

  Serial.println(CLR_BLUE_B "\n=== HARDWARE BRING-UP SUMMARY ===" CLR_RESET);
  Serial.println(CLR_GREEN "[Logger] OK" CLR_RESET);

  if (SPIFFS.begin(true)) {
    Serial.println(CLR_GREEN "[SPIFFS] Mounted" CLR_RESET);
  } else {
    Serial.println(CLR_RED "[SPIFFS] ERROR: mount failed" CLR_RESET);
  }

  Serial.println(CLR_BLUE_B "\n=== NETWORK BRING-UP ===" CLR_RESET);
  Serial.print(CLR_YELLOW "[WiFi] Connecting to SSID: " CLR_RESET);
  Serial.print(NETWORK_SSID);

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);
  WiFi.begin(NETWORK_SSID, NETWORK_PSK);

  Serial.print(CLR_YELLOW "[WiFi] Connecting" CLR_RESET);

  uint32_t t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < 15000) {
    Serial.print(".");
    delay(300);
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println(CLR_GREEN "[WiFi] Connected" CLR_RESET);
    Serial.printf(CLR_MAGENTA_B "[WiFi] IP: " CLR_RESET);
    Serial.println(WiFi.localIP());
  } else {
    Serial.println(CLR_RED "[WiFi] ERROR: connect timeout. Check 2.4GHz/WPA2 and password." CLR_RESET);
  }

  if (MDNS.begin(MDNS_HOSTNAME)) {
    Serial.printf(CLR_GREEN "[mDNS] Responder started (%s.local)\n" CLR_RESET, MDNS_HOSTNAME);
  } else {
    Serial.println(CLR_RED "[mDNS] ERROR: Failed to start responder" CLR_RESET);
  }

  server
    .serveStatic("/", SPIFFS, "/")
    .setDefaultFile("index.html");

  server.on("/api/status", HTTP_GET, [](AsyncWebServerRequest *request) {
    digitalWrite(REQUEST_INDICATOR_LED_PIN, HIGH);

    String json = "{";
    json += "\"ip\":\"" + WiFi.localIP().toString() + "\",";
    json += "\"rssi\":" + String(WiFi.RSSI()) + ",";
    json += "\"uptime_seconds\":" + String(millis() / 1000) + ",";
    json += "\"heap\":" + String(ESP.getFreeHeap());
    json += "}";

    request->send(200, "application/json; charset=utf-8", json);

    digitalWrite(REQUEST_INDICATOR_LED_PIN, LOW);
  });

  server.on("/health", HTTP_GET, [](AsyncWebServerRequest *request) {
    request->send(200, "text/plain; charset=utf-8", "ok");
  });

  server.on("/ready", HTTP_GET, [](AsyncWebServerRequest *request) {
    if (WiFi.status() == WL_CONNECTED) {
      request->send(200, "text/plain; charset=utf-8", "ready");
    } else {
      request->send(503, "text/plain; charset=utf-8", "not ready");
    }
  });

  server.onNotFound([](AsyncWebServerRequest *request) {
    digitalWrite(REQUEST_INDICATOR_LED_PIN, HIGH);
    request->send(404, "text/plain; charset=utf-8", "404: Not found");
    digitalWrite(REQUEST_INDICATOR_LED_PIN, LOW);
  });

  server.begin();
  Serial.println(CLR_GREEN "[HTTP] Async server started on port 80" CLR_RESET);
}

void loop() {}
