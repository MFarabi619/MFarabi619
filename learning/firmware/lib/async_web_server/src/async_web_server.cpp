#include "async_web_server.h"

AsyncWebServer server(80);

void initialize_led_pins() {
  pinMode(REQUEST_INDICATOR_LED_PIN, OUTPUT);
  digitalWrite(REQUEST_INDICATOR_LED_PIN, LOW);
  pinMode(LED_TOGGLE, OUTPUT);
  digitalWrite(LED_TOGGLE, LOW);
}

String formatUptime(unsigned long ms) {
  unsigned long s = ms / 1000UL;
  unsigned long d = s / 86400UL;
  s %= 86400UL;
  unsigned long h = s / 3600UL;
  s %= 3600UL;
  unsigned long m = s / 60UL;
  s %= 60UL;

  char buf[48];
  if (d)
    snprintf(buf, sizeof(buf), "%lud %luh %lum %lus", d, h, m, s);
  else if (h)
    snprintf(buf, sizeof(buf), "%luh %lum %lus", h, m, s);
  else if (m)
    snprintf(buf, sizeof(buf), "%lum %lus", m, s);
  else
    snprintf(buf, sizeof(buf), "%lus", s);
  return String(buf);
}

void begin_async_web_server() {
  initialize_led_pins();
  setup_spiffs();
  begin_wifi();

  server.begin();
  Serial.println(CLR_GREEN "[HTTP] Async server started on port 80" CLR_RESET);

  server.serveStatic("/", SPIFFS, "/").setDefaultFile("index.html");

  server.onNotFound([](AsyncWebServerRequest *request) {
    digitalWrite(REQUEST_INDICATOR_LED_PIN, HIGH);
    String message = "404 — Nothing here\n\nURI: " + request->url();
    request->send(404, "text/plain; charset=utf-8", message);
    digitalWrite(REQUEST_INDICATOR_LED_PIN, LOW);
  });

  server.on("/health", HTTP_GET, [](AsyncWebServerRequest *request) {
    request->send(200, "text/plain; charset=utf-8", "ok");
  });

  server.on("/on", HTTP_GET, [](AsyncWebServerRequest *request) {
    digitalWrite(LED_TOGGLE, HIGH);
    led_toggle_state = 1;
    request->send(200, "text/plain; charset=utf-8", "ON");
  });

  server.on("/off", HTTP_GET, [](AsyncWebServerRequest *request) {
    digitalWrite(LED_TOGGLE, LOW);
    led_toggle_state = 0;
    request->send(200, "text/plain; charset=utf-8", "OFF");
  });

  server.on("/api/status", HTTP_GET, [](AsyncWebServerRequest *request) {
    digitalWrite(REQUEST_INDICATOR_LED_PIN, HIGH);

    String json = "{";
    json += "\"ip\":\"" + WiFi.localIP().toString() + "\",";
    json += "\"rssi\":" + String(WiFi.RSSI()) + ",";
    json += "\"uptime\":\"" + formatUptime(millis()) + "\",";
    json += "\"uptime_seconds\":" + String(millis() / 1000) + ",";
    json += "\"heap\":" + String(ESP.getFreeHeap()) + ",";
    json += "\"gpio_state\":" + String(led_toggle_state);
    json += "}";

    request->send(200, "application/json; charset=utf-8", json);

    digitalWrite(REQUEST_INDICATOR_LED_PIN, LOW);
  });

  server.on("/metrics", HTTP_GET, [](AsyncWebServerRequest *req) {
    int32_t rssi = WiFi.RSSI();
    uint32_t heap_free = ESP.getFreeHeap();
    uint32_t heap_big = heap_caps_get_largest_free_block(MALLOC_CAP_DEFAULT);
    float cpu_temp = temperatureRead();

    String m;
    m.reserve(512);

    m += "wifi_rssi_dbm " + String(rssi) + "\n";
    m += "heap_free_bytes " + String(heap_free) + "\n";
    m += "heap_largest_block_bytes " + String(heap_big) + "\n";
    m += "cpu_temperature_celsius " + String(cpu_temp, 2) + "\n";
    m += "uptime_seconds " + String(millis() / 1000) + "\n";
    m += "uptime_millis " + String(millis()) + "\n";
    m += "gpio_state " + String(led_toggle_state) + "\n";
    m += "reset_reason " + String((int)esp_reset_reason()) + "\n";

    req->send(200, "text/plain; charset=utf-8", m);
  });
}
