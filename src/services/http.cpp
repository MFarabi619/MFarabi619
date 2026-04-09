#include "http.h"

#include <Arduino.h>
#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include <AsyncJson.h>
#include <ArduinoJson.h>
#include <LittleFS.h>
#include <SD.h>

static AsyncWebServer server(CONFIG_HTTP_PORT);
AsyncEventSource http_events("/events");

// ─────────────────────────────────────────────────────────────────────────────
//  Middleware
// ─────────────────────────────────────────────────────────────────────────────

static AsyncCorsMiddleware cors;
static AsyncLoggingMiddleware logging;

// ─────────────────────────────────────────────────────────────────────────────
//  Routes
// ─────────────────────────────────────────────────────────────────────────────

static void api_status(AsyncWebServerRequest *request) {
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();

  root["hostname"]       = WiFi.getHostname();
  root["platform"]       = CONFIG_PLATFORM;
  root["uptime_seconds"] = millis() / 1000;
  root["heap_free"]      = ESP.getFreeHeap();
  root["heap_total"]     = ESP.getHeapSize();
  root["ip"]             = WiFi.localIP().toString();
  root["rssi"]           = WiFi.RSSI();
  root["sdk"]            = ESP.getSdkVersion();

  response->setLength();
  request->send(response);
}

static void api_heap(AsyncWebServerRequest *request) {
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();

  root["heap_total"]     = ESP.getHeapSize();
  root["heap_free"]      = ESP.getFreeHeap();
  root["heap_min_free"]  = ESP.getMinFreeHeap();
  root["heap_max_alloc"] = ESP.getMaxAllocHeap();
  root["psram_total"]    = ESP.getPsramSize();
  root["psram_free"]     = ESP.getFreePsram();

  response->setLength();
  request->send(response);
}

static void api_wifi(AsyncWebServerRequest *request) {
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();

  root["connected"] = WiFi.isConnected();
  root["ssid"]      = WiFi.SSID();
  root["ip"]        = WiFi.localIP().toString();
  root["rssi"]      = WiFi.RSSI();
  root["mac"]       = WiFi.macAddress();

  response->setLength();
  request->send(response);
}

static void api_files(AsyncWebServerRequest *request) {
  if (!SD.begin(CONFIG_SD_CS_GPIO)) {
    request->send(503, "application/json", "{\"error\":\"no SD card\"}");
    return;
  }

  AsyncJsonResponse *response = new AsyncJsonResponse(true);
  JsonArray root = response->getRoot().to<JsonArray>();

  File dir = SD.open("/");
  File entry = dir.openNextFile();
  while (entry) {
    JsonObject file = root.add<JsonObject>();
    file["name"] = String(entry.name());
    file["size"] = (unsigned long)entry.size();
    file["dir"]  = entry.isDirectory();
    entry = dir.openNextFile();
  }
  dir.close();

  response->setLength();
  request->send(response);
}

static void api_upload_handler(AsyncWebServerRequest *request, String filename,
                               size_t index, uint8_t *data, size_t len, bool final) {
  if (!index) {
    String path = "/" + filename;
    request->_tempFile = SD.open(path.c_str(), FILE_WRITE, true);
    if (!request->_tempFile) return;
    Serial.printf("[http] upload: %s\n", filename.c_str());
  }

  if (request->_tempFile && len)
    request->_tempFile.write(data, len);

  if (final && request->_tempFile) {
    request->_tempFile.close();
    Serial.printf("[http] upload complete: %s (%u bytes)\n",
                  filename.c_str(), (unsigned)(index + len));
  }
}

static void api_upload_complete(AsyncWebServerRequest *request) {
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["status"] = "ok";
  response->setLength();
  request->send(response);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Server Init
// ─────────────────────────────────────────────────────────────────────────────

void http_server_start(void) {
  cors.setOrigin("*");
  cors.setMethods("GET, POST, OPTIONS");
  cors.setHeaders("Content-Type");
  server.addMiddleware(&cors);

  logging.setOutput(Serial);
  logging.setEnabled(true);
  server.addMiddleware(&logging);

  http_events.onConnect([](AsyncEventSourceClient *client) {
    client->send("connected", "status", millis(), 5000);
  });
  server.addHandler(&http_events);

  server.on("/api/status", HTTP_GET, api_status);
  server.on("/api/heap",   HTTP_GET, api_heap);
  server.on("/api/wifi",   HTTP_GET, api_wifi);
  server.on("/api/files",  HTTP_GET, api_files);
  server.on("/api/upload", HTTP_POST, api_upload_complete, api_upload_handler);

  server.serveStatic("/", LittleFS, "/www/")
    .setDefaultFile("index.html")
    .setCacheControl("max-age=3600");

  server.onNotFound([](AsyncWebServerRequest *request) {
    request->send(404, "application/json", "{\"error\":\"not found\"}");
  });

  server.begin();
  Serial.printf("[http] listening on port %d\n", CONFIG_HTTP_PORT);
}
