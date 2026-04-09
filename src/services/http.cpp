#include "http.h"

#include <Arduino.h>
#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include <LittleFS.h>
#include <SD.h>

static AsyncWebServer server(CONFIG_HTTP_PORT);

// CORS headers for API access from web frontends
static void add_cors_headers(AsyncWebServerResponse *response) {
  response->addHeader("Access-Control-Allow-Origin", "*");
  response->addHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  response->addHeader("Access-Control-Allow-Headers", "Content-Type");
}

void http_server_start(void) {
  // OPTIONS preflight for CORS
  server.on("/*", HTTP_OPTIONS, [](AsyncWebServerRequest *request) {
    AsyncWebServerResponse *response = request->beginResponse(204);
    add_cors_headers(response);
    request->send(response);
  });

  // GET /api/status — device status
  server.on("/api/status", HTTP_GET, [](AsyncWebServerRequest *request) {
    char buf[512];
    unsigned long secs = millis() / 1000;
    snprintf(buf, sizeof(buf),
      "{"
        "\"hostname\":\"%s\","
        "\"platform\":\"esp32s3\","
        "\"uptime_seconds\":%lu,"
        "\"heap_free\":%u,"
        "\"heap_total\":%u,"
        "\"ip\":\"%s\","
        "\"rssi\":%d,"
        "\"sdk\":\"%s\""
      "}",
      WiFi.getHostname(),
      secs,
      ESP.getFreeHeap(),
      ESP.getHeapSize(),
      WiFi.localIP().toString().c_str(),
      WiFi.RSSI(),
      ESP.getSdkVersion());

    AsyncWebServerResponse *response = request->beginResponse(200, "application/json", buf);
    add_cors_headers(response);
    request->send(response);
  });

  // GET /api/heap — memory details
  server.on("/api/heap", HTTP_GET, [](AsyncWebServerRequest *request) {
    char buf[256];
    snprintf(buf, sizeof(buf),
      "{"
        "\"heap_total\":%u,"
        "\"heap_free\":%u,"
        "\"heap_min_free\":%u,"
        "\"heap_max_alloc\":%u,"
        "\"psram_total\":%u,"
        "\"psram_free\":%u"
      "}",
      ESP.getHeapSize(), ESP.getFreeHeap(),
      ESP.getMinFreeHeap(), ESP.getMaxAllocHeap(),
      ESP.getPsramSize(), ESP.getFreePsram());

    AsyncWebServerResponse *response = request->beginResponse(200, "application/json", buf);
    add_cors_headers(response);
    request->send(response);
  });

  // GET /api/wifi — wifi info
  server.on("/api/wifi", HTTP_GET, [](AsyncWebServerRequest *request) {
    char buf[256];
    snprintf(buf, sizeof(buf),
      "{"
        "\"connected\":%s,"
        "\"ssid\":\"%s\","
        "\"ip\":\"%s\","
        "\"rssi\":%d,"
        "\"mac\":\"%s\""
      "}",
      WiFi.isConnected() ? "true" : "false",
      WiFi.SSID().c_str(),
      WiFi.localIP().toString().c_str(),
      WiFi.RSSI(),
      WiFi.macAddress().c_str());

    AsyncWebServerResponse *response = request->beginResponse(200, "application/json", buf);
    add_cors_headers(response);
    request->send(response);
  });

  // GET /api/files — SD card root directory listing
  server.on("/api/files", HTTP_GET, [](AsyncWebServerRequest *request) {
    if (!SD.begin(CONFIG_SD_CS_GPIO)) {
      AsyncWebServerResponse *response = request->beginResponse(503, "application/json",
        "{\"error\":\"no SD card\"}");
      add_cors_headers(response);
      request->send(response);
      return;
    }

    String json = "[";
    File root = SD.open("/");
    File entry = root.openNextFile();
    bool first = true;
    while (entry) {
      if (!first) json += ",";
      json += "{\"name\":\"";
      json += entry.name();
      json += "\",\"size\":";
      json += String((unsigned long)entry.size());
      json += ",\"dir\":";
      json += entry.isDirectory() ? "true" : "false";
      json += "}";
      first = false;
      entry = root.openNextFile();
    }
    root.close();
    json += "]";

    AsyncWebServerResponse *response = request->beginResponse(200, "application/json", json);
    add_cors_headers(response);
    request->send(response);
  });

  // Serve static files from LittleFS at /
  server.serveStatic("/", LittleFS, "/www/").setDefaultFile("index.html");

  // 404
  server.onNotFound([](AsyncWebServerRequest *request) {
    AsyncWebServerResponse *response = request->beginResponse(404, "application/json",
      "{\"error\":\"not found\"}");
    add_cors_headers(response);
    request->send(response);
  });

  server.begin();
  Serial.printf("[http] server started on port %d\n", CONFIG_HTTP_PORT);
}
