#include "http.h"
#include "cloudevents.h"
#include "../networking/wifi.h"

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

static bool upload_ok = false;

static void api_upload_handler(AsyncWebServerRequest *request, String filename,
                               size_t index, uint8_t *data, size_t len, bool final) {
  if (!index) {
    upload_ok = false;
    if (!SD.begin(CONFIG_SD_CS_GPIO)) return;
    String path = "/" + filename;
    request->_tempFile = SD.open(path.c_str(), FILE_WRITE, true);
    if (!request->_tempFile) return;
    upload_ok = true;
    Serial.printf("[http] upload: %s\n", filename.c_str());
  }

  if (upload_ok && request->_tempFile && len) {
    if (request->_tempFile.write(data, len) != len)
      upload_ok = false;
  }

  if (final) {
    if (request->_tempFile) request->_tempFile.close();
    if (upload_ok)
      Serial.printf("[http] upload complete: %s (%u bytes)\n",
                    filename.c_str(), (unsigned)(index + len));
  }
}

static void api_upload_complete(AsyncWebServerRequest *request) {
  AsyncJsonResponse *response = new AsyncJsonResponse();
  response->setCode(upload_ok ? 200 : 500);
  JsonObject root = response->getRoot().to<JsonObject>();
  root["status"] = upload_ok ? "ok" : "error";
  response->setLength();
  request->send(response);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Device Status (CloudEvent format — matches web app's DeviceStatusEnvelope)
// ─────────────────────────────────────────────────────────────────────────────

static String format_uptime_string(uint32_t seconds) {
  uint32_t days = seconds / 86400;
  uint32_t hours = (seconds % 86400) / 3600;
  uint32_t minutes = (seconds % 3600) / 60;
  uint32_t secs = seconds % 60;
  char buf[32];
  if (days > 0)
    snprintf(buf, sizeof(buf), "%lud %luh %lum %lus", days, hours, minutes, secs);
  else if (hours > 0)
    snprintf(buf, sizeof(buf), "%luh %lum %lus", hours, minutes, secs);
  else
    snprintf(buf, sizeof(buf), "%lum %lus", minutes, secs);
  return String(buf);
}

static void api_device_status(AsyncWebServerRequest *request) {
  String location = "sd";
  if (request->hasParam("location"))
    location = request->getParam("location")->value();

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();

  // time
  time_t now = time(nullptr);
  if (now > 0) {
    struct tm utc;
    gmtime_r(&now, &utc);
    char time_buf[32];
    strftime(time_buf, sizeof(time_buf), "%Y-%m-%dT%H:%M:%SZ", &utc);
    root["time"] = time_buf;
  } else {
    root["time"] = "";
  }

  JsonObject data = root["data"].to<JsonObject>();

  // device
  JsonObject device = data["device"].to<JsonObject>();
  device["chip_model"] = ESP.getChipModel();
  device["chip_cores"] = ESP.getChipCores();
  device["chip_revision"] = (uint32_t)ESP.getChipRevision();

  // network
  JsonObject network = data["network"].to<JsonObject>();
  network["ipv4_address"] = WiFi.localIP().toString();
  network["wifi_rssi"] = WiFi.RSSI();

  // runtime
  uint32_t uptime_seconds = millis() / 1000;
  JsonObject runtime = data["runtime"].to<JsonObject>();
  runtime["uptime"] = format_uptime_string(uptime_seconds);
  runtime["uptime_seconds"] = uptime_seconds;
  runtime["memory_heap_bytes"] = ESP.getFreeHeap();

  // storage
  JsonObject storage = data["storage"].to<JsonObject>();
  storage["location"] = location;
  if (location == "littlefs") {
    storage["total_bytes"] = LittleFS.totalBytes();
    storage["used_bytes"] = LittleFS.usedBytes();
    storage["free_bytes"] = LittleFS.totalBytes() - LittleFS.usedBytes();
  } else {
    if (SD.begin(CONFIG_SD_CS_GPIO)) {
      storage["total_bytes"] = SD.totalBytes();
      storage["used_bytes"] = SD.usedBytes();
      storage["free_bytes"] = SD.totalBytes() - SD.usedBytes();
    } else {
      storage["total_bytes"] = 0;
      storage["used_bytes"] = 0;
      storage["free_bytes"] = 0;
    }
  }

  response->setLength();
  request->send(response);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Filesystem API (matches web app's FileEntry)
// ─────────────────────────────────────────────────────────────────────────────

static void api_filesystem_list(AsyncWebServerRequest *request) {
  String location = "sd";
  if (request->hasParam("location"))
    location = request->getParam("location")->value();

  AsyncJsonResponse *response = new AsyncJsonResponse(true);
  JsonArray root = response->getRoot().to<JsonArray>();

  if (location == "littlefs") {
    File dir = LittleFS.open("/");
    if (dir) {
      File entry = dir.openNextFile();
      while (entry) {
        JsonObject file = root.add<JsonObject>();
        file["name"] = String(entry.name());
        file["size"] = (unsigned long)entry.size();
        entry = dir.openNextFile();
      }
      dir.close();
    }
  } else {
    if (SD.begin(CONFIG_SD_CS_GPIO)) {
      File dir = SD.open("/");
      if (dir) {
        File entry = dir.openNextFile();
        while (entry) {
          JsonObject file = root.add<JsonObject>();
          file["name"] = String(entry.name());
          file["size"] = (unsigned long)entry.size();
          entry = dir.openNextFile();
        }
        dir.close();
      }
    }
  }

  response->setLength();
  request->send(response);
}

static void api_filesystem_delete(AsyncWebServerRequest *request) {
  if (!request->hasParam("path") || !request->hasParam("location")) {
    request->send(400, "application/json",
                  "{\"ok\":false,\"error\":\"missing path or location\"}");
    return;
  }

  String path = request->getParam("path")->value();
  String location = request->getParam("location")->value();
  bool removed = false;

  if (location == "littlefs") {
    removed = LittleFS.remove(path);
  } else {
    if (SD.begin(CONFIG_SD_CS_GPIO))
      removed = SD.remove(path);
  }

  AsyncJsonResponse *response = new AsyncJsonResponse();
  response->setCode(removed ? 200 : 404);
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = removed;
  response->setLength();
  request->send(response);
}

// ─────────────────────────────────────────────────────────────────────────────
//  CO2 Sensor API (stub — returns "no sensor" when SCD30/SCD4x not present)
// ─────────────────────────────────────────────────────────────────────────────

static void api_co2_config_get(AsyncWebServerRequest *request) {
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = false;
  JsonObject data = root["data"].to<JsonObject>();
  data["model"] = "none";
  data["measuring"] = false;
  data["measurement_interval_seconds"] = 0;
  data["auto_calibration_enabled"] = false;
  data["temperature_offset_celsius"] = 0.0;
  data["altitude_meters"] = 0;
  response->setLength();
  request->send(response);
}

static void api_co2_config_set(AsyncWebServerRequest *request) {
  request->send(200, "application/json",
                "{\"ok\":false,\"error\":\"no CO2 sensor connected\"}");
}

static void api_co2_start(AsyncWebServerRequest *request) {
  request->send(200, "application/json",
                "{\"ok\":false,\"error\":\"no CO2 sensor connected\"}");
}

static void api_co2_stop(AsyncWebServerRequest *request) {
  request->send(200, "application/json",
                "{\"ok\":false,\"error\":\"no CO2 sensor connected\"}");
}

// ─────────────────────────────────────────────────────────────────────────────
//  Access Point Config API
// ─────────────────────────────────────────────────────────────────────────────

static void api_ap_config_get(AsyncWebServerRequest *request) {
  char ap_ssid[33] = {0};
  char ap_pass[65] = {0};
  wifi_get_ap_ssid(ap_ssid, sizeof(ap_ssid));
  wifi_get_ap_password(ap_pass, sizeof(ap_pass));

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = true;
  JsonObject data = root["data"].to<JsonObject>();
  data["ssid"] = ap_ssid;
  data["password"] = ap_pass;
  data["enabled"] = wifi_get_ap_enabled();
  data["active"] = wifi_is_ap_active();
  data["ip"] = wifi_is_ap_active() ? WiFi.softAPIP().toString() : "0.0.0.0";
  response->setLength();
  request->send(response);
}

// ─────────────────────────────────────────────────────────────────────────────
//  WiFi Provisioning API (matches web app's api.rs types)
// ─────────────────────────────────────────────────────────────────────────────

static const char *wifi_encryption_string(wifi_auth_mode_t auth) {
  switch (auth) {
    case WIFI_AUTH_OPEN:            return "open";
    case WIFI_AUTH_WEP:             return "wep";
    case WIFI_AUTH_WPA_PSK:         return "wpa";
    case WIFI_AUTH_WPA2_PSK:        return "wpa2";
    case WIFI_AUTH_WPA_WPA2_PSK:    return "wpa_wpa2";
    case WIFI_AUTH_WPA2_ENTERPRISE: return "wpa2_enterprise";
    case WIFI_AUTH_WPA3_PSK:        return "wpa3";
    case WIFI_AUTH_WPA2_WPA3_PSK:   return "wpa2_wpa3";
    default:                        return "unknown";
  }
}

static void fill_wireless_status(JsonObject &data) {
  data["connected"]  = wifi_is_connected();
  data["mode"]       = wifi_is_ap_active() ? "ap_sta" : "sta";
  data["tenant"]     = CONFIG_CLOUDEVENTS_TENANT;
  data["sta_ssid"]   = wifi_is_connected() ? WiFi.SSID() : "";
  data["sta_ipv4"]   = wifi_is_connected() ? WiFi.localIP().toString() : "0.0.0.0";
  data["wifi_rssi"]  = wifi_is_connected() ? WiFi.RSSI() : 0;
  data["ap_active"]  = wifi_is_ap_active();
  data["ap_ssid"]    = wifi_is_ap_active() ? CONFIG_AP_SSID : "";
  data["ap_ipv4"]    = wifi_is_ap_active() ? WiFi.softAPIP().toString() : "0.0.0.0";
}

static void api_wireless_status(AsyncWebServerRequest *request) {
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = true;
  JsonObject data = root["data"].to<JsonObject>();
  fill_wireless_status(data);
  response->setLength();
  request->send(response);
}

static void api_wireless_scan(AsyncWebServerRequest *request) {
  int16_t count = WiFi.scanNetworks();

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = (count >= 0);
  JsonObject data = root["data"].to<JsonObject>();
  data["scan_count"] = (count >= 0) ? count : 0;

  JsonArray networks = data["networks"].to<JsonArray>();
  for (int16_t index = 0; index < count; index++) {
    JsonObject network = networks.add<JsonObject>();
    network["ssid"]       = WiFi.SSID(index);
    network["rssi"]       = WiFi.RSSI(index);
    network["channel"]    = WiFi.channel(index);
    network["encryption"] = wifi_encryption_string(WiFi.encryptionType(index));
    network["open"]       = (WiFi.encryptionType(index) == WIFI_AUTH_OPEN);
  }
  WiFi.scanDelete();

  response->setLength();
  request->send(response);
}

// Handled via AsyncCallbackJsonWebHandler — see registration in http_server_start()

// ─────────────────────────────────────────────────────────────────────────────
//  Captive Portal
// ─────────────────────────────────────────────────────────────────────────────

static bool is_captive_portal_request(AsyncWebServerRequest *request) {
  if (!wifi_is_ap_active()) return false;

  String host = request->host();
  if (host.isEmpty()) return true;
  if (host == WiFi.softAPIP().toString()) return false;
  if (host == CONFIG_HOSTNAME || host == String(CONFIG_HOSTNAME) + ".local") return false;
  return true;
}

static void captive_portal_redirect(AsyncWebServerRequest *request) {
  String location = "http://" + WiFi.softAPIP().toString() + "/";
  request->redirect(location);
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

  // Device status (CloudEvent format for web dashboard)
  server.on("/api/system/device/status", HTTP_GET, api_device_status);

  // Filesystem (location-aware)
  server.on("/api/filesystem/list",   HTTP_GET,    api_filesystem_list);
  server.on("/api/filesystem/delete", HTTP_DELETE, api_filesystem_delete);

  // CO2 sensor (stub — returns "no sensor" until SCD30/SCD4x is connected)
  server.on("/api/co2/config", HTTP_GET,  api_co2_config_get);
  server.on("/api/co2/config", HTTP_POST, api_co2_config_set);
  server.on("/api/co2/start",  HTTP_POST, api_co2_start);
  server.on("/api/co2/stop",   HTTP_POST, api_co2_stop);

  // WiFi provisioning API (matches web app's network_panel.rs)
  server.on("/api/wireless/status",          HTTP_GET,  api_wireless_status);
  server.on("/api/wireless/actions/scan",    HTTP_POST, api_wireless_scan);

  // Access point config
  server.on("/api/ap/config", HTTP_GET, api_ap_config_get);

  // AP config set (JSON body: {"ssid":"...", "password":"...", "enabled": bool})
  static AsyncCallbackJsonWebHandler *ap_config_handler =
      new AsyncCallbackJsonWebHandler("/api/ap/config",
          [](AsyncWebServerRequest *request, JsonVariant &json) {
    JsonObject body = json.as<JsonObject>();

    if (body.containsKey("ssid") && body.containsKey("password")) {
      const char *ssid = body["ssid"] | "";
      const char *password = body["password"] | "";
      wifi_set_ap_config(ssid, password);

      // Restart AP with new config if currently active
      if (wifi_is_ap_active()) {
        wifi_stop_ap();
        wifi_start_ap();
      }
    }

    if (body.containsKey("enabled")) {
      bool enabled = body["enabled"] | true;
      wifi_set_ap_enabled(enabled);
    }

    // Return current config
    char ap_ssid[33] = {0};
    wifi_get_ap_ssid(ap_ssid, sizeof(ap_ssid));

    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = true;
    JsonObject data = root["data"].to<JsonObject>();
    data["ssid"] = ap_ssid;
    data["enabled"] = wifi_get_ap_enabled();
    data["active"] = wifi_is_ap_active();
    data["ip"] = wifi_is_ap_active() ? WiFi.softAPIP().toString() : "0.0.0.0";
    response->setLength();
    request->send(response);
  });
  server.addHandler(ap_config_handler);

  // Connect accepts JSON body {"ssid":"...","password":"..."}
  static AsyncCallbackJsonWebHandler *connect_handler =
      new AsyncCallbackJsonWebHandler("/api/wireless/actions/connect",
          [](AsyncWebServerRequest *request, JsonVariant &json) {
    JsonObject body = json.as<JsonObject>();
    String ssid = body["ssid"] | "";
    String password = body["password"] | "";
    ssid.trim();

    if (ssid.isEmpty()) {
      request->send(400, "application/json",
                    "{\"ok\":false,\"error\":{\"code\":\"SSID_REQUIRED\","
                    "\"message\":\"Missing ssid parameter\"}}");
      return;
    }

    wifi_set_credentials(ssid.c_str(), password.c_str());
    WiFi.begin(ssid.c_str(), password.c_str());

    int result = WiFi.waitForConnectResult(CONFIG_WIFI_TIMEOUT_MS);

    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = (result == WL_CONNECTED);
    JsonObject data = root["data"].to<JsonObject>();
    data["attempted_ssid"] = ssid;
    data["status_code"] = result;
    fill_wireless_status(data);

    if (result != WL_CONNECTED) {
      wifi_start_ap();
    }

    response->setLength();
    request->send(response);
  });
  server.addHandler(connect_handler);

  // Captive portal detection URLs — redirect to AP root when AP is active
  auto cp_redirect = [](AsyncWebServerRequest *request) {
    if (wifi_is_ap_active()) {
      captive_portal_redirect(request);
    } else {
      request->send(204);
    }
  };
  server.on("/generate_204",       HTTP_GET, cp_redirect);
  server.on("/gen_204",            HTTP_GET, cp_redirect);
  server.on("/fwlink",             HTTP_GET, cp_redirect);
  server.on("/redirect",           HTTP_GET, cp_redirect);
  server.on("/hotspot-detect.html", HTTP_GET, cp_redirect);
  server.on("/canonical.html",     HTTP_GET, cp_redirect);
  server.on("/connecttest.txt",    HTTP_GET, cp_redirect);
  server.on("/ncsi.txt",           HTTP_GET, cp_redirect);

  cloudevents_register_routes(&server);

  server.serveStatic("/", LittleFS, "/www/")
    .setDefaultFile("index.html")
    .setCacheControl("max-age=3600");

  server.onNotFound([](AsyncWebServerRequest *request) {
    if (is_captive_portal_request(request)) {
      captive_portal_redirect(request);
      return;
    }
    request->send(404, "application/json", "{\"error\":\"not found\"}");
  });

  server.begin();
  Serial.printf("[http] listening on port %d\n", CONFIG_HTTP_PORT);
}
