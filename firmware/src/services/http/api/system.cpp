#include "system.h"
#include "../../../config.h"
#include "../../../services/system.h"
#include "../../../networking/update.h"

#include <Arduino.h>
#include <AsyncJson.h>
#include <ArduinoJson.h>

#include <time.h>

namespace {

void handle_device_status(AsyncWebServerRequest *request) {
  StorageKind storage_kind = StorageKind::SD;
  if (request->hasParam("location")) {
    String location = request->getParam("location")->value();
    if (location == "littlefs") storage_kind = StorageKind::LittleFS;
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

  SystemQuery query = {
    .preferred_storage = storage_kind,
    .snapshot = {},
  };
  services::system::accessSnapshot(&query);

  JsonObject data = root["data"].to<JsonObject>();

  JsonObject device = data["device"].to<JsonObject>();
  device["hostname"] = query.snapshot.identity.hostname;
  device["platform"] = config::PLATFORM;
  device["sdk_version"] = query.snapshot.sdk_version;
  device["idf_version"] = query.snapshot.idf_version;
  device["arduino_version"] = query.snapshot.arduino_version;
  device["chip_model"] = query.snapshot.chip_model;
  device["chip_cores"] = query.snapshot.chip_cores;
  device["chip_revision"] = query.snapshot.chip_revision;
  device["cpu_mhz"] = query.snapshot.cpu_mhz;
  device["sketch_md5"] = query.snapshot.sketch_md5;
  device["sketch_size"] = query.snapshot.sketch_size;
  device["sketch_free"] = query.snapshot.sketch_free;
  device["flash_size"] = query.snapshot.flash_size;
  device["flash_speed_mhz"] = query.snapshot.flash_speed_mhz;

  JsonObject network = data["network"].to<JsonObject>();
  network["connected"] = query.snapshot.network.connected;
  network["ssid"] = query.snapshot.network.ssid;
  network["ipv4_address"] = query.snapshot.network.ip;
  network["wifi_rssi"] = query.snapshot.network.rssi;
  network["mac_address"] = query.snapshot.network.mac;

  JsonObject runtime = data["runtime"].to<JsonObject>();
  char uptime_buf[32] = {0};
  services::system::formatUptime(uptime_buf, sizeof(uptime_buf), query.snapshot.uptime_seconds);
  runtime["uptime"] = uptime_buf;
  runtime["uptime_seconds"] = query.snapshot.uptime_seconds;
  runtime["temperature_celsius"] = query.snapshot.chip_temperature_celsius;
  runtime["memory_heap_free"] = query.snapshot.heap_free;
  runtime["memory_heap_total"] = query.snapshot.heap_total;
  runtime["memory_heap_min_free"] = query.snapshot.heap_min_free;
  runtime["memory_heap_max_alloc"] = query.snapshot.heap_max_alloc;
  runtime["memory_psram_total"] = query.snapshot.psram_total;
  runtime["memory_psram_free"] = query.snapshot.psram_free;

  JsonObject sleep = data["sleep"].to<JsonObject>();
  sleep["pending"] = query.snapshot.sleep.pending;
  sleep["requested_duration_seconds"] = query.snapshot.sleep.requested_duration_seconds;
  sleep["wake_cause"] = query.snapshot.sleep.wake_cause;
  sleep["timer_wakeup_enabled"] = query.snapshot.sleep.timer_wakeup_enabled;
  sleep["timer_wakeup_us"] = (unsigned long long)query.snapshot.sleep.timer_wakeup_us;
  sleep["enabled"] = query.snapshot.sleep.config_enabled;
  sleep["default_duration_seconds"] = query.snapshot.sleep.default_duration_seconds;

  JsonObject logger = data["data_logger"].to<JsonObject>();
  logger["initialized"] = query.snapshot.data_logger.initialized;
  logger["sd_ready"] = query.snapshot.data_logger.sd_ready;
  logger["header_written"] = query.snapshot.data_logger.header_written;
  logger["interval_ms"] = query.snapshot.data_logger.interval_ms;
  logger["last_log_ms"] = query.snapshot.data_logger.last_log_ms;
  logger["path"] = query.snapshot.data_logger.path;

  JsonObject storage = data["storage"].to<JsonObject>();
  storage["location"] = (query.snapshot.storage.kind == StorageKind::LittleFS) ? "littlefs" : "sd";
  storage["mounted"] = query.snapshot.storage.mounted;
  storage["total_bytes"] = query.snapshot.storage.total_bytes;
  storage["used_bytes"] = query.snapshot.storage.used_bytes;
  storage["free_bytes"] = query.snapshot.storage.free_bytes;

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

void handle_sleep_config_get(AsyncWebServerRequest *request) {
  SleepConfig config = {};
  if (!power::sleep::accessConfig(&config)) {
    request->send(500, "application/json", "{\"ok\":false,\"error\":\"sleep config unavailable\"}");
    return;
  }

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = true;
  JsonObject data = root["data"].to<JsonObject>();
  data["enabled"] = config.enabled;
  data["duration_seconds"] = config.duration_seconds;
  response->setLength();
  request->send(response);
}

}

void services::http::api::system::registerRoutes(AsyncWebServer &server,
                                                 AsyncRateLimitMiddleware &reset_limit,
                                                 AsyncRateLimitMiddleware &ota_limit) {
  server.on("/api/system/device/status", HTTP_GET, handle_device_status);
  server.on("/api/system/device/actions/reset", HTTP_POST, handle_device_reset)
    .addMiddleware(&reset_limit);
  server.on("/api/system/sleep/config", HTTP_GET, handle_sleep_config_get);

  AsyncCallbackJsonWebHandler &sleep_config_handler =
      server.on("/api/system/sleep/config", HTTP_POST,
          [](AsyncWebServerRequest *request, JsonVariant &json) {
    SleepConfig config = {};
    if (!power::sleep::accessConfig(&config)) {
      request->send(500, "application/json", "{\"ok\":false,\"error\":\"sleep config unavailable\"}");
      return;
    }

    JsonObject body = json.as<JsonObject>();
    config.enabled = body["enabled"] | config.enabled;
    config.duration_seconds = body["duration_seconds"] | config.duration_seconds;

    if (!power::sleep::storeConfig(&config)) {
      request->send(400, "application/json", "{\"ok\":false,\"error\":\"invalid sleep config\"}");
      return;
    }

    if (!config.enabled) {
      power::sleep::abortPending();
    }

    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = true;
    JsonObject data = root["data"].to<JsonObject>();
    data["enabled"] = config.enabled;
    data["duration_seconds"] = config.duration_seconds;
    response->setLength();
    request->send(response);
  });
  sleep_config_handler.setMaxContentLength(256);

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
