#include "system.h"
#include "../../../config.h"
#include "../../../networking/update.h"

#include <Arduino.h>
#include <WiFi.h>
#include <AsyncJson.h>
#include <ArduinoJson.h>
#include <LittleFS.h>
#include <SD.h>

#include <time.h>

namespace {

String format_uptime_string(uint32_t seconds) {
  uint32_t days = seconds / 86400;
  uint32_t hours = (seconds % 86400) / 3600;
  uint32_t minutes = (seconds % 3600) / 60;
  uint32_t secs = seconds % 60;
  char buf[32];
  if (days > 0) {
    snprintf(buf, sizeof(buf), "%lud %luh %lum %lus", days, hours, minutes, secs);
  } else if (hours > 0) {
    snprintf(buf, sizeof(buf), "%luh %lum %lus", hours, minutes, secs);
  } else {
    snprintf(buf, sizeof(buf), "%lum %lus", minutes, secs);
  }
  return String(buf);
}

void handle_device_status(AsyncWebServerRequest *request) {
  String location = "sd";
  if (request->hasParam("location")) {
    location = request->getParam("location")->value();
  }

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = true;

  time_t now = time(nullptr);
  if (now > 0) {
    struct tm utc_time;
    gmtime_r(&now, &utc_time);
    char time_buf[32];
    strftime(time_buf, sizeof(time_buf), "%Y-%m-%dT%H:%M:%SZ", &utc_time);
    root["time"] = time_buf;
  } else {
    root["time"] = "";
  }

  JsonObject data = root["data"].to<JsonObject>();

  JsonObject device = data["device"].to<JsonObject>();
  device["hostname"] = WiFi.getHostname();
  device["platform"] = config::PLATFORM;
  device["sdk_version"] = ESP.getSdkVersion();
  device["idf_version"] = esp_get_idf_version();
  device["arduino_version"] = ESP_ARDUINO_VERSION_STR;
  device["chip_model"] = ESP.getChipModel();
  device["chip_cores"] = ESP.getChipCores();
  device["chip_revision"] = (uint32_t)ESP.getChipRevision();
  device["cpu_mhz"] = ESP.getCpuFreqMHz();
  device["sketch_md5"] = ESP.getSketchMD5();
  device["sketch_size"] = ESP.getSketchSize();
  device["sketch_free"] = ESP.getFreeSketchSpace();
  device["flash_size"] = ESP.getFlashChipSize();
  device["flash_speed_mhz"] = ESP.getFlashChipSpeed() / 1000000;

  JsonObject network = data["network"].to<JsonObject>();
  network["connected"] = WiFi.isConnected();
  network["ssid"] = WiFi.SSID();
  network["ipv4_address"] = WiFi.localIP().toString();
  network["wifi_rssi"] = WiFi.RSSI();
  network["mac_address"] = WiFi.macAddress();

  uint32_t uptime_seconds = millis() / 1000;
  JsonObject runtime = data["runtime"].to<JsonObject>();
  runtime["uptime"] = format_uptime_string(uptime_seconds);
  runtime["uptime_seconds"] = uptime_seconds;
  runtime["temperature_celsius"] = temperatureRead();
  runtime["memory_heap_free"] = ESP.getFreeHeap();
  runtime["memory_heap_total"] = ESP.getHeapSize();
  runtime["memory_heap_min_free"] = ESP.getMinFreeHeap();
  runtime["memory_heap_max_alloc"] = ESP.getMaxAllocHeap();
  runtime["memory_psram_total"] = ESP.getPsramSize();
  runtime["memory_psram_free"] = ESP.getFreePsram();

  JsonObject storage = data["storage"].to<JsonObject>();
  storage["location"] = location;
  if (location == "littlefs") {
    storage["total_bytes"] = LittleFS.totalBytes();
    storage["used_bytes"] = LittleFS.usedBytes();
    storage["free_bytes"] = LittleFS.totalBytes() - LittleFS.usedBytes();
  } else if (SD.begin()) {
    storage["total_bytes"] = SD.totalBytes();
    storage["used_bytes"] = SD.usedBytes();
    storage["free_bytes"] = SD.totalBytes() - SD.usedBytes();
  } else {
    storage["total_bytes"] = 0;
    storage["used_bytes"] = 0;
    storage["free_bytes"] = 0;
  }

  response->setLength();
  request->send(response);
}

void handle_device_reset(AsyncWebServerRequest *request) {
  request->send(200, "application/json", "{\"ok\":true,\"message\":\"rebooting\"}");
  xTaskCreate(
      [](void *arg) {
        (void)arg;
        vTaskDelay(pdMS_TO_TICKS(100));
        ESP.restart();
      },
      "http-reset", 2048, nullptr, 1, nullptr);
}

}

void services::http::api::system::registerRoutes(AsyncWebServer &server,
                                                 AsyncRateLimitMiddleware &reset_limit,
                                                 AsyncRateLimitMiddleware &ota_limit) {
  server.on("/api/system/device/status", HTTP_GET, handle_device_status);
  server.on("/api/system/device/actions/reset", HTTP_POST, handle_device_reset)
    .addMiddleware(&reset_limit);

  server.on("/api/system/ota/rollback", HTTP_GET,
            [](AsyncWebServerRequest *request) {
    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["can_rollback"] = ::networking::update::canRollback();
    response->setLength();
    request->send(response);
  });

  server.on("/api/system/ota/rollback", HTTP_POST,
            [](AsyncWebServerRequest *request) {
    bool ok = ::networking::update::rollback();
    AsyncJsonResponse *response = new AsyncJsonResponse();
    response->setCode(ok ? 200 : 400);
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = ok;
    if (ok) root["message"] = "rollback set — reboot to activate";
    response->setLength();
    request->send(response);
  }).addMiddleware(&ota_limit);

  AsyncCallbackJsonWebHandler &ota_url_handler =
      server.on("/api/system/ota/url", HTTP_POST,
          [](AsyncWebServerRequest *request, JsonVariant &json) {
    JsonObject body = json.as<JsonObject>();
    String url = body["url"] | "";
    if (url.isEmpty()) {
      request->send(400, "application/json", "{\"ok\":false,\"error\":\"missing url\"}");
      return;
    }

    request->send(200, "application/json", "{\"ok\":true,\"message\":\"update started\"}");

    String url_copy = url;
    xTaskCreate([](void *arg) {
      String *update_url = (String *)arg;
      bool ok = ::networking::update::applyFromURL(update_url->c_str());
      delete update_url;
      if (ok) {
        Serial.println(F("[ota] rebooting..."));
        delay(500);
        ESP.restart();
      }
      vTaskDelete(nullptr);
    }, "ota-url", 8192, new String(url_copy), 1, nullptr);
  });
  ota_url_handler.setMaxContentLength(1024);
  ota_url_handler.addMiddleware(&ota_limit);

  server.on("/api/system/ota/sd", HTTP_POST,
            [](AsyncWebServerRequest *request) {
    bool ok = ::networking::update::applyFromSD();
    if (ok) {
      request->send(200, "application/json", "{\"ok\":true,\"message\":\"rebooting\"}");
      delay(500);
      ESP.restart();
    } else {
      request->send(400, "application/json", "{\"ok\":false,\"error\":\"no update.bin on SD\"}");
    }
  }).addMiddleware(&ota_limit);
}
