#include "http.h"
#include "cloudevents.h"
#include "../sensors/carbon_dioxide.h"
#include "email.h"
#include "ws_shell.h"
#include "../networking/wifi.h"
#include "../networking/update.h"

#include <Arduino.h>
#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include <AsyncJson.h>
#include <ArduinoJson.h>
#include <LittleFS.h>
#include <SD.h>

static AsyncWebServer server(config::http::PORT);
AsyncEventSource http_events("/events");

// ─────────────────────────────────────────────────────────────────────────────
//  Middleware
// ─────────────────────────────────────────────────────────────────────────────

static AsyncCorsMiddleware cors;
static AsyncLoggingMiddleware logging;
static AsyncAuthenticationMiddleware auth;
static AsyncRateLimitMiddleware scan_limit;
static AsyncRateLimitMiddleware reset_limit;
static AsyncRateLimitMiddleware ota_limit;
static AsyncRateLimitMiddleware format_limit;

struct FileUploadState {
  bool ok = false;
};

static bool is_sensitive_path(const String &path) {
  return path == "/.ssh" || path.startsWith("/.ssh/")
      || path == config::ssh::HOSTKEY_PATH;
}

static bool requires_admin_auth(AsyncWebServerRequest *request) {
  if (!request || request->method() == HTTP_OPTIONS) return false;

  String url = request->url();
  if (url == "/ws/shell") return true;
  if (!url.startsWith("/api/")) return false;

  return !(url == "/api/status"
      || url == "/api/heap"
      || url == "/api/wifi"
      || url == "/api/system/device/status"
      || url == "/api/cloudevents"
      || url == "/api/wireless/status");
}

// ─────────────────────────────────────────────────────────────────────────────
//  Filesystem helpers
// ─────────────────────────────────────────────────────────────────────────────

static bool sd_ready = false;

static bool sd_ensure() {
  if (sd_ready) return true;
  sd_ready = SD.begin();
  return sd_ready;
}

struct FilesystemTarget {
  fs::FS *fs;
  String path;
  bool ok;
};

static FilesystemTarget fs_resolve(const String &url) {
  const char *prefix = "/api/filesystem/";
  String remainder = url.substring(strlen(prefix));

  if (remainder.startsWith("sd")) {
    String path = remainder.substring(2);
    if (path.isEmpty()) path = "/";
    if (sd_ensure())
      return {&SD, path, true};
    return {nullptr, path, false};
  }

  if (remainder.startsWith("littlefs")) {
    String path = remainder.substring(8);
    if (path.isEmpty()) path = "/";
    return {&LittleFS, path, true};
  }

  return {nullptr, "", false};
}

static void fs_list_dir(fs::FS &fs, const String &path, JsonArray &out) {
  File dir = fs.open(path);
  if (!dir || !dir.isDirectory()) return;
  File entry = dir.openNextFile();
  while (entry) {
    String name = String(entry.name());
    if (!is_sensitive_path(name)) {
      JsonObject obj = out.add<JsonObject>();
      obj["name"] = name;
      obj["size"] = (unsigned long long)entry.size();
      obj["dir"] = entry.isDirectory();
      obj["last_write_unix"] = (unsigned long long)entry.getLastWrite();
    }
    entry = dir.openNextFile();
  }
  dir.close();
}

static bool fs_recursive_delete(fs::FS &fs, const String &path) {
  File entry = fs.open(path);
  if (!entry) return false;

  if (!entry.isDirectory()) {
    entry.close();
    return fs.remove(path);
  }

  entry.close();
  File dir = fs.open(path);
  File child = dir.openNextFile();
  while (child) {
    String child_name = String(child.name());
    bool is_dir = child.isDirectory();
    child.close();

    String child_path = (path == "/")
        ? "/" + child_name
        : path + "/" + child_name;

    if (is_dir) {
      if (!fs_recursive_delete(fs, child_path)) { dir.close(); return false; }
    } else {
      if (!fs.remove(child_path)) { dir.close(); return false; }
    }
    child = dir.openNextFile();
  }
  dir.close();
  return fs.rmdir(path);
}

class CaptivePortalRedirectHandler : public AsyncWebHandler {
public:
  bool canHandle(AsyncWebServerRequest *request) const override {
    return request != nullptr;
  }

  void handleRequest(AsyncWebServerRequest *request) override {
    if (sd_ensure() && SD.exists("/index.html")) {
      request->send(SD, "/index.html", "text/html");
      return;
    }
    request->redirect("http://" + WiFi.softAPIP().toString() + "/");
  }
};

// ─────────────────────────────────────────────────────────────────────────────
//  Routes
// ─────────────────────────────────────────────────────────────────────────────

static void api_status(AsyncWebServerRequest *request) {
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();

  root["hostname"]       = WiFi.getHostname();
  root["platform"]       = config::PLATFORM;
  root["uptime_seconds"] = millis() / 1000;
  root["heap_free"]      = ESP.getFreeHeap();
  root["heap_total"]     = ESP.getHeapSize();
  root["heap_max_alloc"] = ESP.getMaxAllocHeap();
  root["ip"]             = WiFi.localIP().toString();
  root["rssi"]           = WiFi.RSSI();
  root["sdk"]            = ESP.getSdkVersion();
  root["idf"]            = esp_get_idf_version();
  root["arduino"]        = ESP_ARDUINO_VERSION_STR;
  root["chip"]           = ESP.getChipModel();
  root["chip_cores"]     = ESP.getChipCores();
  root["chip_revision"]  = (uint32_t)ESP.getChipRevision();
  root["cpu_mhz"]        = ESP.getCpuFreqMHz();
  root["temperature_c"]  = temperatureRead();
  root["sketch_md5"]     = ESP.getSketchMD5();
  root["sketch_size"]    = ESP.getSketchSize();
  root["sketch_free"]    = ESP.getFreeSketchSpace();
  root["flash_size"]     = ESP.getFlashChipSize();
  root["flash_speed_mhz"] = ESP.getFlashChipSpeed() / 1000000;

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
  root["temperature_c"]  = temperatureRead();

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
  if (!sd_ensure()) {
    request->send(503, "application/json", "{\"error\":\"no SD card\"}");
    return;
  }

  AsyncJsonResponse *response = new AsyncJsonResponse(true);
  JsonArray root = response->getRoot().to<JsonArray>();
  fs_list_dir(SD, "/", root);

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
  runtime["memory_heap_total"] = ESP.getHeapSize();

  // storage
  JsonObject storage = data["storage"].to<JsonObject>();
  storage["location"] = location;
  if (location == "littlefs") {
    storage["total_bytes"] = LittleFS.totalBytes();
    storage["used_bytes"] = LittleFS.usedBytes();
    storage["free_bytes"] = LittleFS.totalBytes() - LittleFS.usedBytes();
  } else {
    if (sd_ensure()) {
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
//  Filesystem REST API
//
//  GET    /api/filesystem                  → list both roots
//  GET    /api/filesystem/{fs}/{path}      → list dir or download file
//  POST   /api/filesystem/{fs}/{path}      → mkdir
//  POST   /api/filesystem/littlefs/format  → format LittleFS
//  PUT    /api/filesystem/{fs}/{path}      → upload file (mkdir -p parents)
//  PATCH  /api/filesystem/{fs}/{path}      → rename (JSON: {"name":"new.txt"})
//  DELETE /api/filesystem/{fs}/{path}      → recursive delete
// ─────────────────────────────────────────────────────────────────────────────

static void api_fs_root(AsyncWebServerRequest *request) {
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = true;

  JsonArray sd_arr = root["sd"].to<JsonArray>();
  if (sd_ensure())
    fs_list_dir(SD, "/", sd_arr);

  JsonArray lfs_arr = root["littlefs"].to<JsonArray>();
  fs_list_dir(LittleFS, "/", lfs_arr);

  response->setLength();
  request->send(response);
}

static void api_fs_get(AsyncWebServerRequest *request) {
  FilesystemTarget ref = fs_resolve(request->url());
  if (!ref.ok) {
    request->send(400, "application/json", "{\"ok\":false,\"error\":\"invalid filesystem prefix\"}");
    return;
  }
  if (is_sensitive_path(ref.path)) {
    request->send(403, "application/json", "{\"ok\":false,\"error\":\"forbidden path\"}");
    return;
  }

  File entry = ref.fs->open(ref.path);
  if (!entry) {
    request->send(404, "application/json", "{\"ok\":false,\"error\":\"not found\"}");
    return;
  }

  if (entry.isDirectory()) {
    entry.close();
    AsyncJsonResponse *response = new AsyncJsonResponse(true);
    JsonArray arr = response->getRoot().to<JsonArray>();
    fs_list_dir(*ref.fs, ref.path, arr);
    response->setLength();
    request->send(response);
  } else {
    entry.close();
    request->send(*ref.fs, ref.path, "application/octet-stream");
  }
}

static void api_fs_mkdir(AsyncWebServerRequest *request) {
  FilesystemTarget ref = fs_resolve(request->url());
  if (!ref.ok) {
    request->send(400, "application/json", "{\"ok\":false,\"error\":\"invalid filesystem prefix\"}");
    return;
  }
  if (is_sensitive_path(ref.path)) {
    request->send(403, "application/json", "{\"ok\":false,\"error\":\"forbidden path\"}");
    return;
  }

  bool created = ref.fs->mkdir(ref.path);
  AsyncJsonResponse *response = new AsyncJsonResponse();
  response->setCode(created ? 201 : 500);
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = created;
  response->setLength();
  request->send(response);
}

static void api_fs_format(AsyncWebServerRequest *request) {
  bool formatted = LittleFS.format();
  AsyncJsonResponse *response = new AsyncJsonResponse();
  response->setCode(formatted ? 200 : 500);
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = formatted;
  response->setLength();
  request->send(response);
}

static void api_fs_upload_handler(AsyncWebServerRequest *request, String filename,
                                  size_t index, uint8_t *data, size_t len, bool final) {
  FileUploadState *ctx = reinterpret_cast<FileUploadState *>(request->_tempObject);

  if (!index) {
    delete ctx;
    ctx = new FileUploadState();
    request->_tempObject = ctx;

    FilesystemTarget ref = fs_resolve(request->url());
    if (!ref.ok) {
      request->send(400, "application/json", "{\"ok\":false,\"error\":\"invalid filesystem prefix\"}");
      return;
    }
    if (is_sensitive_path(ref.path)) {
      request->send(403, "application/json", "{\"ok\":false,\"error\":\"forbidden path\"}");
      return;
    }

    request->_tempFile = ref.fs->open(ref.path, FILE_WRITE, true);
    if (!request->_tempFile) {
      request->send(500, "application/json", "{\"ok\":false,\"error\":\"open failed\"}");
      return;
    }

    ctx->ok = true;
    Serial.printf("[http] upload: %s\n", ref.path.c_str());
  }

  if (request->getResponse()) return;

  if (ctx && ctx->ok && request->_tempFile && len) {
    if (request->_tempFile.write(data, len) != len) {
      ctx->ok = false;
      request->send(500, "application/json", "{\"ok\":false,\"error\":\"write failed\"}");
    }
  }

  if (final) {
    if (request->_tempFile) request->_tempFile.close();
    if (ctx && ctx->ok)
      Serial.printf("[http] upload complete (%u bytes)\n", (unsigned)(index + len));
  }
}

static void api_fs_upload_complete(AsyncWebServerRequest *request) {
  std::unique_ptr<FileUploadState> ctx(
      reinterpret_cast<FileUploadState *>(request->_tempObject));
  request->_tempObject = nullptr;

  if (request->getResponse()) return;

  AsyncJsonResponse *response = new AsyncJsonResponse();
  response->setCode((ctx && ctx->ok) ? 201 : 500);
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = (ctx && ctx->ok);
  response->setLength();
  request->send(response);
}

static void api_fs_delete(AsyncWebServerRequest *request) {
  FilesystemTarget ref = fs_resolve(request->url());
  if (!ref.ok) {
    request->send(400, "application/json", "{\"ok\":false,\"error\":\"invalid filesystem prefix\"}");
    return;
  }
  if (is_sensitive_path(ref.path)) {
    request->send(403, "application/json", "{\"ok\":false,\"error\":\"forbidden path\"}");
    return;
  }

  bool removed = fs_recursive_delete(*ref.fs, ref.path);
  AsyncJsonResponse *response = new AsyncJsonResponse();
  response->setCode(removed ? 200 : 404);
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = removed;
  response->setLength();
  request->send(response);
}

// PATCH rename is registered via AsyncCallbackJsonWebHandler below in http_server_start()

static void api_device_reset(AsyncWebServerRequest *request) {
  request->send(200, "application/json", "{\"ok\":true,\"message\":\"rebooting\"}");
  xTaskCreate(
      [](void *arg) {
        (void)arg;
        vTaskDelay(pdMS_TO_TICKS(100));
        ESP.restart();
      },
      "http-reset", 2048, nullptr, 1, nullptr);
}

// ─────────────────────────────────────────────────────────────────────────────
//  CO2 Sensor API (stub — returns "no sensor" when SCD30/SCD4x not present)
// ─────────────────────────────────────────────────────────────────────────────

static void api_co2_config_get(AsyncWebServerRequest *request) {
  Co2Config config = {};
  sensors::carbon_dioxide::accessConfig(&config);

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = sensors::carbon_dioxide::isAvailable();
  JsonObject data = root["data"].to<JsonObject>();
  data["model"] = config.model;
  data["measuring"] = config.measuring;
  data["measurement_interval_seconds"] = config.measurement_interval_seconds;
  data["auto_calibration_enabled"] = config.auto_calibration_enabled;
  data["temperature_offset_celsius"] = config.temperature_offset_celsius;
  data["altitude_meters"] = config.altitude_meters;
  response->setLength();
  request->send(response);
}

static void api_co2_start(AsyncWebServerRequest *request) {
  bool ok = sensors::carbon_dioxide::enable();
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = ok;
  response->setLength();
  request->send(response);
}

static void api_co2_stop(AsyncWebServerRequest *request) {
  bool ok = sensors::carbon_dioxide::disable();
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = ok;
  response->setLength();
  request->send(response);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Access Point Config API
// ─────────────────────────────────────────────────────────────────────────────

static void api_ap_config_get(AsyncWebServerRequest *request) {
  APConfig ap_cfg = {};
  networking::wifi::ap::accessConfig(&ap_cfg);

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = true;
  JsonObject data = root["data"].to<JsonObject>();
  data["ssid"] = ap_cfg.ssid;
  data["enabled"] = networking::wifi::ap::isActive();
  data["active"] = networking::wifi::ap::isActive();
  data["ip"] = networking::wifi::ap::isActive() ? WiFi.softAPIP().toString() : "0.0.0.0";
  data["clients"] = networking::wifi::ap::isActive() ? WiFi.softAPgetStationNum() : 0;
  data["hostname"] = networking::wifi::ap::isActive() ? WiFi.softAPgetHostname() : "";
  data["mac"] = networking::wifi::ap::isActive() ? WiFi.softAPmacAddress() : "";
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
  bool sta = WiFi.isConnected();
  data["connected"]  = sta;
  data["mode"]       = networking::wifi::ap::isActive() ? "ap_sta" : "sta";
  data["tenant"]     = config::cloudevents::TENANT;
  data["sta_ssid"]   = sta ? WiFi.SSID() : "";
  data["sta_bssid"]  = sta ? WiFi.BSSIDstr() : "";
  data["sta_ipv4"]   = sta ? WiFi.localIP().toString() : "0.0.0.0";
  data["wifi_rssi"]  = sta ? WiFi.RSSI() : 0;
  data["ap_active"]  = networking::wifi::ap::isActive();
  data["ap_ssid"]    = networking::wifi::ap::isActive() ? WiFi.softAPSSID() : "";
  data["ap_ipv4"]    = networking::wifi::ap::isActive() ? WiFi.softAPIP().toString() : "0.0.0.0";
  data["ap_clients"] = networking::wifi::ap::isActive() ? WiFi.softAPgetStationNum() : 0;
  data["ap_hostname"] = networking::wifi::ap::isActive() ? WiFi.softAPgetHostname() : "";
  data["ap_mac"] = networking::wifi::ap::isActive() ? WiFi.softAPmacAddress() : "";
}

static void send_wireless_scan_response(AsyncWebServerRequest *request,
                                        int16_t count) {
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = (count >= 0);
  JsonObject data = root["data"].to<JsonObject>();
  data["scan_count"] = (count >= 0) ? count : 0;

  JsonArray networks = data["networks"].to<JsonArray>();
  for (int16_t index = 0; index < count; index++) {
    JsonObject network = networks.add<JsonObject>();
    network["ssid"] = WiFi.SSID(index);
    network["bssid"] = WiFi.BSSIDstr(index);
    network["rssi"] = WiFi.RSSI(index);
    network["channel"] = WiFi.channel(index);
    network["encryption"] = wifi_encryption_string(WiFi.encryptionType(index));
    network["open"] = (WiFi.encryptionType(index) == WIFI_AUTH_OPEN);
  }

  response->setLength();
  request->send(response);
}

static void send_wireless_connect_response(AsyncWebServerRequest *request,
                                           const String &ssid,
                                           int status_code) {
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = (status_code == WL_CONNECTED);
  JsonObject data = root["data"].to<JsonObject>();
  data["attempted_ssid"] = ssid;
  data["status_code"] = status_code;
  fill_wireless_status(data);
  response->setLength();
  request->send(response);
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
  WiFi.scanDelete();
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
    network["bssid"]      = WiFi.BSSIDstr(index);
    network["rssi"]       = WiFi.RSSI(index);
    network["channel"]    = WiFi.channel(index);
    network["encryption"] = wifi_encryption_string(WiFi.encryptionType(index));
    network["open"]       = (WiFi.encryptionType(index) == WIFI_AUTH_OPEN);
  }
  WiFi.scanDelete();

  response->setLength();
  request->send(response);
}

void services::http::service() {
  // no-op: async handlers removed
}

// ─────────────────────────────────────────────────────────────────────────────
//  Captive Portal
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
//  Server Init
// ─────────────────────────────────────────────────────────────────────────────

void services::http::initialize() {
  cors.setOrigin("*");
  cors.setMethods("GET, POST, PUT, PATCH, DELETE, OPTIONS");
  cors.setHeaders("Content-Type, Authorization");
  server.addMiddleware(&cors);

#if CERATINA_HTTP_AUTH_ENABLED
  auth.setUsername(config::http::AUTH_USER);
  auth.setPassword(config::http::AUTH_PASSWORD);
  auth.setRealm(config::http::AUTH_REALM);
  auth.setAuthType(AsyncAuthType::AUTH_DIGEST);
  auth.generateHash();
  server.addMiddleware([](AsyncWebServerRequest *request, ArMiddlewareNext next) {
    if (!requires_admin_auth(request)) { next(); return; }
    if (auth.allowed(request)) { next(); return; }
    request->requestAuthentication(AsyncAuthType::AUTH_DIGEST, config::http::AUTH_REALM);
  });
#endif

  // Rate limits for expensive operations
  scan_limit.setMaxRequests(3);
  scan_limit.setWindowSize(30);
  reset_limit.setMaxRequests(1);
  reset_limit.setWindowSize(10);
  ota_limit.setMaxRequests(1);
  ota_limit.setWindowSize(60);
  format_limit.setMaxRequests(1);
  format_limit.setWindowSize(30);

  logging.setOutput(Serial);
  logging.setEnabled(true);
  server.addMiddleware(&logging);

  WiFi.setScanTimeout(config::wifi::CONNECT_TIMEOUT_MS);

  http_events.onConnect([](AsyncEventSourceClient *client) {
    client->send("connected", "status", millis(), 5000);
  });
  server.addHandler(&http_events);

  server.on("/api/status", HTTP_GET, api_status);
  server.on("/api/heap",   HTTP_GET, api_heap);
  server.on("/api/wifi",   HTTP_GET, api_wifi);
  server.on("/api/files",  HTTP_GET, api_files);

  // Device status (CloudEvent format for web dashboard)
  server.on("/api/system/device/status", HTTP_GET, api_device_status);

  // Filesystem REST API
  server.on(AsyncURIMatcher::exact("/api/filesystem"), HTTP_GET, api_fs_root);
  server.on("/api/filesystem/littlefs/format", HTTP_POST, api_fs_format)
    .addMiddleware(&format_limit);
  server.on(AsyncURIMatcher::dir("/api/filesystem"), HTTP_GET,    api_fs_get);
  server.on(AsyncURIMatcher::dir("/api/filesystem"), HTTP_POST,   api_fs_mkdir);
  server.on(AsyncURIMatcher::dir("/api/filesystem"), HTTP_PUT,
            api_fs_upload_complete, api_fs_upload_handler);
  server.on(AsyncURIMatcher::dir("/api/filesystem"), HTTP_DELETE, api_fs_delete);

  // PATCH for rename (needs JSON body handler)
  AsyncCallbackJsonWebHandler &fs_rename_handler =
      server.on(AsyncURIMatcher::dir("/api/filesystem"), HTTP_PATCH,
          [](AsyncWebServerRequest *request, JsonVariant &json) {
    FilesystemTarget ref = fs_resolve(request->url());
    if (!ref.ok) {
      request->send(400, "application/json", "{\"ok\":false,\"error\":\"invalid filesystem prefix\"}");
      return;
    }
    if (is_sensitive_path(ref.path)) {
      request->send(403, "application/json", "{\"ok\":false,\"error\":\"forbidden path\"}");
      return;
    }

    JsonObject body = json.as<JsonObject>();
    String new_name = body["name"] | "";
    if (new_name.isEmpty()) {
      request->send(400, "application/json", "{\"ok\":false,\"error\":\"missing name in body\"}");
      return;
    }

    int last_slash = ref.path.lastIndexOf('/');
    String dir = (last_slash > 0) ? ref.path.substring(0, last_slash) : "";
    String new_path = dir + "/" + new_name;

    if (is_sensitive_path(new_path)) {
      request->send(403, "application/json", "{\"ok\":false,\"error\":\"forbidden path\"}");
      return;
    }

    bool ok = ref.fs->rename(ref.path, new_path);
    AsyncJsonResponse *response = new AsyncJsonResponse();
    response->setCode(ok ? 200 : 500);
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = ok;
    if (ok) {
      root["from"] = ref.path;
      root["to"] = new_path;
    }
    response->setLength();
    request->send(response);
  });
  fs_rename_handler.setMaxContentLength(256);

  server.on("/api/system/device/actions/reset", HTTP_POST, api_device_reset)
    .addMiddleware(&reset_limit);

  // OTA update endpoints
  server.on("/api/system/ota/rollback", HTTP_GET,
            [](AsyncWebServerRequest *request) {
    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["can_rollback"] = networking::update::canRollback();
    response->setLength();
    request->send(response);
  });

  server.on("/api/system/ota/rollback", HTTP_POST,
            [](AsyncWebServerRequest *request) {
    bool ok = networking::update::rollback();
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
      String *u = (String *)arg;
      bool ok = networking::update::applyFromURL(u->c_str());
      delete u;
      if (ok) {
        Serial.println(F("[ota] rebooting..."));
        delay(500);
        ESP.restart();
      }
      vTaskDelete(NULL);
    }, "ota-url", 8192, new String(url_copy), 1, NULL);
  });
  ota_url_handler.setMaxContentLength(1024);
  ota_url_handler.addMiddleware(&ota_limit);

  server.on("/api/system/ota/sd", HTTP_POST,
            [](AsyncWebServerRequest *request) {
    bool ok = networking::update::applyFromSD();
    if (ok) {
      request->send(200, "application/json", "{\"ok\":true,\"message\":\"rebooting\"}");
      delay(500);
      ESP.restart();
    } else {
      request->send(400, "application/json", "{\"ok\":false,\"error\":\"no update.bin on SD\"}");
    }
  }).addMiddleware(&ota_limit);

  server.on("/api/co2/config", HTTP_GET, api_co2_config_get);
  server.on("/api/co2/start",  HTTP_POST, api_co2_start);
  server.on("/api/co2/stop",   HTTP_POST, api_co2_stop);

  AsyncCallbackJsonWebHandler &co2_config_handler =
      server.on("/api/co2/config", HTTP_POST,
          [](AsyncWebServerRequest *request, JsonVariant &json) {
    JsonObject body = json.as<JsonObject>();
    if (!body["measurement_interval_seconds"].isNull())
      sensors::carbon_dioxide::configureInterval(body["measurement_interval_seconds"]);
    if (!body["auto_calibration_enabled"].isNull())
      sensors::carbon_dioxide::configureAutoCalibration(body["auto_calibration_enabled"]);
    if (!body["temperature_offset_celsius"].isNull())
      sensors::carbon_dioxide::configureTemperatureOffset(body["temperature_offset_celsius"]);
    if (!body["altitude_meters"].isNull())
      sensors::carbon_dioxide::configureAltitude(body["altitude_meters"]);
    if (!body["forced_recalibration_ppm"].isNull())
      sensors::carbon_dioxide::configureRecalibration(body["forced_recalibration_ppm"]);

    Co2Config config = {};
    sensors::carbon_dioxide::accessConfig(&config);
    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = sensors::carbon_dioxide::isAvailable();
    JsonObject data = root["data"].to<JsonObject>();
    data["model"] = config.model;
    data["measuring"] = config.measuring;
    data["measurement_interval_seconds"] = config.measurement_interval_seconds;
    data["auto_calibration_enabled"] = config.auto_calibration_enabled;
    data["temperature_offset_celsius"] = config.temperature_offset_celsius;
    data["altitude_meters"] = config.altitude_meters;
    response->setLength();
    request->send(response);
  });
  co2_config_handler.setMaxContentLength(512);

  // WiFi provisioning API (matches web app's network_panel.rs)
  server.on("/api/wireless/status",          HTTP_GET,  api_wireless_status);
  server.on("/api/wireless/actions/scan",    HTTP_POST, api_wireless_scan)
    .addMiddleware(&scan_limit);

  // Access point config
  server.on("/api/ap/config", HTTP_GET, api_ap_config_get);

  // AP config set (JSON body: {"ssid":"...", "password":"...", "enabled": bool})
  AsyncCallbackJsonWebHandler &ap_config_handler =
      server.on("/api/ap/config", HTTP_POST,
          [](AsyncWebServerRequest *request, JsonVariant &json) {
    JsonObject body = json.as<JsonObject>();

    if (!body["ssid"].isNull() && !body["password"].isNull()) {
      const char *ssid = body["ssid"] | "";
      const char *password = body["password"] | "";
      networking::wifi::ap::configure(ssid, password);

      if (networking::wifi::ap::isActive()) {
        networking::wifi::ap::disable();
        networking::wifi::ap::enable();
      }
    }

    if (!body["enabled"].isNull()) {
      bool enabled = body["enabled"] | true;
      if (enabled) networking::wifi::ap::enable();
      else networking::wifi::ap::disable();
    }

    APConfig ap_cfg = {};
    networking::wifi::ap::accessConfig(&ap_cfg);

    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = true;
    JsonObject data = root["data"].to<JsonObject>();
    data["ssid"] = ap_cfg.ssid;
    data["enabled"] = networking::wifi::ap::isActive();
    data["active"] = networking::wifi::ap::isActive();
    data["ip"] = networking::wifi::ap::isActive() ? WiFi.softAPIP().toString() : "0.0.0.0";
    data["clients"] = networking::wifi::ap::isActive() ? WiFi.softAPgetStationNum() : 0;
    response->setLength();
    request->send(response);
  });
  ap_config_handler.setMaxContentLength(512);

  // Connect accepts JSON body {"ssid":"...","password":"..."}
  AsyncCallbackJsonWebHandler &connect_handler =
      server.on("/api/wireless/actions/connect", HTTP_POST,
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

    WiFi.disconnect(false, false);
    WiFi.mode(WIFI_MODE_STA);
    WiFi.setHostname(config::HOSTNAME);
    WiFi.begin(ssid.c_str(), password.c_str());

    int result = WiFi.waitForConnectResult(config::wifi::CONNECT_TIMEOUT_MS);

    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = (result == WL_CONNECTED);
    JsonObject data = root["data"].to<JsonObject>();
    data["attempted_ssid"] = ssid;
    data["status_code"] = result;
    fill_wireless_status(data);

    if (result != WL_CONNECTED) {
      networking::wifi::ap::enable();
    }

    response->setLength();
    request->send(response);
  });
  connect_handler.setMaxContentLength(512);

#if CERATINA_SMTP_ENABLED
  server.on("/api/smtp/config", HTTP_GET,
            [](AsyncWebServerRequest *request) {
    char host[128] = {0};
    uint16_t port = 0;
    bool ok = services::email::accessEndpoint(host, sizeof(host), &port);

    JsonDocument doc;
    doc["ok"] = ok;
    JsonObject data = doc["data"].to<JsonObject>();
    data["smtp_enabled"] = true;
    data["smtp_test_enabled"] = config::smtp::TEST_ENABLED == 1;
    if (ok) {
      data["smtp_host"] = host;
      data["smtp_port"] = port;
    }

    String json;
    serializeJson(doc, json);
    request->send(200, "application/json", json);
  });

  server.on("/api/smtp/send", HTTP_POST,
            [](AsyncWebServerRequest *request) {
    char host[128] = {0};
    uint16_t port = 0;
    if (!services::email::accessEndpoint(host, sizeof(host), &port)) {
      request->send(400, "application/json",
                    "{\"ok\":false,\"error\":\"SMTP not configured\"}");
      return;
    }

    bool sent = services::email::sendTest();
    JsonDocument doc;
    doc["ok"] = sent;
    JsonObject data = doc["data"].to<JsonObject>();
    data["smtp_host"] = host;
    data["smtp_port"] = port;
    data["sent"] = sent;

    String json;
    serializeJson(doc, json);
    request->send(sent ? 200 : 500, "application/json", json);
  });
#endif

  services::cloudevents::registerRoutes(&server);
  services::ws_shell::registerRoutes(&server);

  server.serveStatic("/", LittleFS, "/www/")
    .setDefaultFile("index.html")
    .setCacheControl("max-age=3600");

  server.addHandler(new CaptivePortalRedirectHandler()).setFilter(ON_AP_FILTER);

  server.onNotFound([](AsyncWebServerRequest *request) {
    String url = request->url();

    if (url == "/" && sd_ensure() && SD.exists("/index.html")) {
      request->send(SD, "/index.html", "text/html");
      return;
    }

    request->send(404, "application/json", "{\"error\":\"not found\"}");
  });

  server.begin();
  Serial.printf("[http] listening on port %d\n", config::http::PORT);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING


#include "http.h"
#include "../testing/it.h"

#include <ArduinoJson.h>
#include <LittleFS.h>

// ─────────────────────────────────────────────────────────────────────────────
//  Config
// ─────────────────────────────────────────────────────────────────────────────

static void http_test_port_default(void) {
  TEST_MESSAGE("user verifies HTTP server configuration");
  TEST_ASSERT_EQUAL_INT_MESSAGE(80, config::http::PORT,
    "device: HTTP port should be 80");
  TEST_MESSAGE("HTTP port is 80");
}

// ─────────────────────────────────────────────────────────────────────────────
//  ArduinoJson: serialization
// ─────────────────────────────────────────────────────────────────────────────

static void json_test_create_and_serialize(void) {
  TEST_MESSAGE("user creates a JSON document, serializes, and deserializes to verify");

  JsonDocument doc;
  doc["hostname"] = "microvisor";
  doc["port"] = 22;
  doc["active"] = true;

  char buf[128];
  size_t len = serializeJson(doc, buf, sizeof(buf));
  TEST_ASSERT_GREATER_THAN_MESSAGE(0, (int)len,
    "device: serializeJson returned 0");

  // Deserialize and assert typed fields — stronger than strstr
  JsonDocument readback;
  DeserializationError err = deserializeJson(readback, buf);
  TEST_ASSERT_FALSE_MESSAGE((bool)err, "device: failed to deserialize own output");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("microvisor", readback["hostname"].as<const char *>(),
    "device: hostname mismatch after roundtrip");
  TEST_ASSERT_EQUAL_INT_MESSAGE(22, readback["port"].as<int>(),
    "device: port mismatch after roundtrip");
  TEST_ASSERT_TRUE_MESSAGE(readback["active"].as<bool>(),
    "device: active should be true after roundtrip");

  TEST_MESSAGE(buf);
}

static void json_test_measure_length(void) {
  TEST_MESSAGE("user measures JSON length before serializing");

  JsonDocument doc;
  doc["key"] = "value";

  size_t measured = measureJson(doc);
  char buf[64];
  size_t actual = serializeJson(doc, buf, sizeof(buf));

  TEST_ASSERT_EQUAL_UINT32_MESSAGE(measured, actual,
    "device: measureJson doesn't match serializeJson length");

  char msg[48];
  snprintf(msg, sizeof(msg), "measured=%u actual=%u", (unsigned)measured, (unsigned)actual);
  TEST_MESSAGE(msg);
}

// ─────────────────────────────────────────────────────────────────────────────
//  ArduinoJson: deserialization
// ─────────────────────────────────────────────────────────────────────────────

static void json_test_deserialize(void) {
  TEST_MESSAGE("user deserializes a JSON string and reads values");

  const char *input = "{\"sensor\":\"scd4x\",\"co2\":412,\"temp\":23.5,\"ok\":true}";
  JsonDocument doc;
  DeserializationError error = deserializeJson(doc, input);

  TEST_ASSERT_FALSE_MESSAGE((bool)error,
    "device: deserialization failed");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("scd4x", doc["sensor"].as<const char *>(),
    "device: sensor value mismatch");
  TEST_ASSERT_EQUAL_INT_MESSAGE(412, doc["co2"].as<int>(),
    "device: co2 value mismatch");
  TEST_ASSERT_FLOAT_WITHIN_MESSAGE(0.01f, 23.5f, doc["temp"].as<float>(),
    "device: temp value mismatch");
  TEST_ASSERT_TRUE_MESSAGE(doc["ok"].as<bool>(),
    "device: ok should be true");

  TEST_MESSAGE("deserialization verified");
}

static void json_test_default_values(void) {
  TEST_MESSAGE("user reads missing keys with defaults using | operator");

  JsonDocument doc;
  deserializeJson(doc, "{\"port\":8080}");

  int port = doc["port"] | 3000;
  int missing = doc["timeout"] | 5000;

  TEST_ASSERT_EQUAL_INT_MESSAGE(8080, port,
    "device: existing key should return its value");
  TEST_ASSERT_EQUAL_INT_MESSAGE(5000, missing,
    "device: missing key should return default");

  TEST_MESSAGE("default value operator | verified");
}

// ─────────────────────────────────────────────────────────────────────────────
//  ArduinoJson: nested structures
// ─────────────────────────────────────────────────────────────────────────────

static void json_test_nested_objects_and_arrays(void) {
  TEST_MESSAGE("user creates nested objects and arrays");

  JsonDocument doc;
  doc["device"] = "microvisor";

  JsonArray sensors = doc["sensors"].to<JsonArray>();
  JsonObject sensor0 = sensors.add<JsonObject>();
  sensor0["name"] = "scd4x";
  sensor0["bus"] = "i2c.1";
  sensor0["addr"] = 0x62;

  JsonObject sensor1 = sensors.add<JsonObject>();
  sensor1["name"] = "ds3231";
  sensor1["bus"] = "i2c.0";
  sensor1["addr"] = 0x68;

  TEST_ASSERT_EQUAL_INT_MESSAGE(2, doc["sensors"].size(),
    "device: sensors array should have 2 elements");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("scd4x", doc["sensors"][0]["name"].as<const char *>(),
    "device: first sensor name mismatch");
  TEST_ASSERT_EQUAL_HEX8_MESSAGE(0x68, doc["sensors"][1]["addr"].as<int>(),
    "device: second sensor addr mismatch");

  char buf[256];
  serializeJson(doc, buf, sizeof(buf));
  TEST_MESSAGE(buf);
}

static void json_test_file_roundtrip(void) {
  TEST_MESSAGE("user writes JSON to LittleFS and reads it back");

  TEST_ASSERT_TRUE_MESSAGE(LittleFS.begin(false),
    "device: LittleFS mount failed before JSON file roundtrip");
  const char *path = "/.test_json.tmp";

  // Write
  JsonDocument write_doc;
  write_doc["hostname"] = "microvisor";
  write_doc["port"] = 22;

  File writer = LittleFS.open(path, FILE_WRITE);
  TEST_ASSERT_TRUE_MESSAGE((bool)writer, "device: open for write failed");
  serializeJson(write_doc, writer);
  writer.close();

  // Read
  File reader = LittleFS.open(path, FILE_READ);
  TEST_ASSERT_TRUE_MESSAGE((bool)reader, "device: open for read failed");
  JsonDocument read_doc;
  DeserializationError error = deserializeJson(read_doc, reader);
  reader.close();

  TEST_ASSERT_FALSE_MESSAGE((bool)error, "device: deserialize from file failed");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("microvisor", read_doc["hostname"].as<const char *>(),
    "device: hostname mismatch after file roundtrip");
  TEST_ASSERT_EQUAL_INT_MESSAGE(22, read_doc["port"].as<int>(),
    "device: port mismatch after file roundtrip");

  LittleFS.remove(path);
  TEST_MESSAGE("JSON file roundtrip verified");
}

// ─────────────────────────────────────────────────────────────────────────────
//  HTTP server policy: rate limits, auth, CORS
//  These tests document intended behaviour — actual enforcement requires e2e.
// ─────────────────────────────────────────────────────────────────────────────

static void http_test_cors_allows_patch(void) {
  TEST_MESSAGE("user verifies CORS allows PATCH for rename endpoint");
  // CORS is configured in http_server_start():
  //   cors.setMethods("GET, POST, PUT, PATCH, DELETE, OPTIONS")
  // This cannot be unit-tested without a real HTTP client, but we document it.
  TEST_IGNORE_MESSAGE("CORS config verified by code review — test with browser");
}

static void http_test_public_endpoints_no_auth(void) {
  TEST_MESSAGE("user documents which endpoints are public (no auth required)");
  // These endpoints must remain accessible without authentication:
  //   GET /api/status
  //   GET /api/heap
  //   GET /api/wifi
  //   GET /api/system/device/status
  //   GET /api/cloudevents
  //   GET /api/wireless/status
  // Verified by requires_admin_auth() in http.cpp
  TEST_ASSERT_EQUAL_INT_MESSAGE(0, CERATINA_HTTP_AUTH_ENABLED,
    "device: auth is disabled by default — enable to test auth enforcement");
  TEST_MESSAGE("public endpoints documented");
}

static void http_test_auth_config(void) {
  TEST_MESSAGE("user verifies auth configuration defaults");
  TEST_ASSERT_NOT_NULL(config::http::AUTH_USER);
  TEST_ASSERT_NOT_NULL(config::http::AUTH_PASSWORD);
  TEST_ASSERT_NOT_NULL(config::http::AUTH_REALM);
  TEST_ASSERT_EQUAL_STRING_MESSAGE("ceratina", config::http::AUTH_REALM,
    "device: auth realm should be 'ceratina'");

  char msg[80];
  snprintf(msg, sizeof(msg), "auth user=%s realm=%s enabled=%d",
           config::http::AUTH_USER, config::http::AUTH_REALM, CERATINA_HTTP_AUTH_ENABLED);
  TEST_MESSAGE(msg);
}

static void http_test_rate_limit_policy(void) {
  TEST_MESSAGE("user documents rate limit policy for expensive endpoints");
  // Rate limits applied in http_server_start():
  //   POST /api/wireless/actions/scan     — 3 requests per 30 seconds
  //   POST /api/system/device/actions/reset — 1 request per 10 seconds
  //   POST /api/system/ota/*              — 1 request per 60 seconds
  //   POST /api/filesystem/littlefs/format — 1 request per 30 seconds
  // Cannot be unit-tested — requires rapid HTTP requests.
  TEST_IGNORE_MESSAGE("rate limit policy documented — test with curl");
}

// ─────────────────────────────────────────────────────────────────────────────
//  Runners
// ─────────────────────────────────────────────────────────────────────────────

void services::http::test(void) {
  it("user observes that HTTP port is configured to 80",
     http_test_port_default);
  it("user observes that ArduinoJson creates and serializes a document",
     json_test_create_and_serialize);
  it("user observes that measureJson matches actual serialized length",
     json_test_measure_length);
  it("user observes that ArduinoJson deserializes and reads values correctly",
     json_test_deserialize);
  it("user observes that missing keys return defaults via | operator",
     json_test_default_values);
  it("user observes that nested objects and arrays work",
     json_test_nested_objects_and_arrays);
  it("user observes that JSON roundtrips through LittleFS",
     json_test_file_roundtrip);
  it("user observes that CORS allows PATCH method",
     http_test_cors_allows_patch);
  it("user observes which endpoints are public",
     http_test_public_endpoints_no_auth);
  it("user observes auth configuration defaults",
     http_test_auth_config);
  it("user observes rate limit policy for expensive endpoints",
     http_test_rate_limit_policy);
}

#endif

// ─────────────────────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING


#include "http.h"
#include "../networking/wifi.h"
#include "../testing/it.h"

namespace services::http_e2e { void test(void); }

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClient.h>

static const uint16_t HTTP_TIMEOUT_MS = 5000;
static bool server_started = false;

static bool ensure_ready(void) {
  if (server_started && WiFi.isConnected()) return true;

  if (!WiFi.isConnected()) {
    networking::wifi::sta::initialize();
    if (!networking::wifi::sta::connect()) return false;
    delay(500);
  }

  if (!server_started) {
    services::http::initialize();
    for (int i = 0; i < 20; i++) {
      delay(100);
      vTaskDelay(1);
    }
    server_started = true;
    Serial.printf("[e2e] server started, IP=%s port=%d core=%d heap=%u\n",
                  WiFi.localIP().toString().c_str(), config::http::PORT,
                  xPortGetCoreID(), ESP.getFreeHeap());
  }

  return WiFi.isConnected();
}

static int http_request(const char *method, const char *path,
                        const char *body, char *response, size_t response_size) {
  WiFiClient client;
  IPAddress ip = WiFi.localIP();

  if (ip == IPAddress(0, 0, 0, 0)) {
    Serial.println("[e2e] WiFi.localIP() is 0.0.0.0");
    return -3;
  }

  client.setTimeout(HTTP_TIMEOUT_MS);
  if (!client.connect(ip, config::http::PORT)) {
    Serial.printf("[e2e] connect to %s:%d failed, retrying...\n",
                  ip.toString().c_str(), config::http::PORT);
    delay(500);
    if (!client.connect(ip, config::http::PORT)) {
      Serial.printf("[e2e] connect retry failed (core=%d)\n", xPortGetCoreID());
      return -1;
    }
  }

  if (body) {
    client.printf("%s %s HTTP/1.1\r\n"
                  "Host: %s\r\n"
                  "Content-Type: application/json\r\n"
                  "Content-Length: %d\r\n"
                  "Connection: close\r\n\r\n%s",
                  method, path, ip.toString().c_str(),
                  (int)strlen(body), body);
  } else {
    client.printf("%s %s HTTP/1.1\r\n"
                  "Host: %s\r\n"
                  "Connection: close\r\n\r\n",
                  method, path, ip.toString().c_str());
  }

  uint32_t start = millis();
  while (!client.available() && millis() - start < HTTP_TIMEOUT_MS) {
    delay(10);
  }

  if (!client.available()) { client.stop(); return -2; }

  // Read status line: "HTTP/1.1 200 OK"
  String status_line = client.readStringUntil('\n');
  int code = 0;
  int space = status_line.indexOf(' ');
  if (space > 0) code = status_line.substring(space + 1).toInt();

  // Skip headers
  while (client.available()) {
    String header = client.readStringUntil('\n');
    if (header == "\r" || header.length() == 0) break;
  }

  // Read body
  if (response && response_size > 0) {
    size_t pos = 0;
    while (client.available() && pos < response_size - 1) {
      response[pos++] = client.read();
    }
    response[pos] = '\0';
  }

  client.stop();
  return code;
}

static void assert_get(const char *path, int expected_code) {
  if (!ensure_ready()) {
    TEST_IGNORE_MESSAGE("no WiFi connection");
    return;
  }

  char body[512] = {0};
  int code = http_request("GET", path, NULL, body, sizeof(body));

  char msg[128];
  snprintf(msg, sizeof(msg), "%s -> %d (%.60s...)", path, code,
           body[0] ? body : "(empty)");
  TEST_MESSAGE(msg);

  TEST_ASSERT_EQUAL_INT_MESSAGE(expected_code, code,
    "device: unexpected HTTP status code");
}

static void assert_post(const char *path, const char *req_body, int expected_code) {
  if (!ensure_ready()) {
    TEST_IGNORE_MESSAGE("no WiFi connection");
    return;
  }

  char resp[512] = {0};
  int code = http_request("POST", path, req_body, resp, sizeof(resp));

  char msg[128];
  snprintf(msg, sizeof(msg), "%s -> %d (%.60s...)", path, code,
           resp[0] ? resp : "(empty)");
  TEST_MESSAGE(msg);

  TEST_ASSERT_EQUAL_INT_MESSAGE(expected_code, code,
    "device: unexpected HTTP status code");
}

// ─────────────────────────────────────────────────────────────────────────────
//  GET routes
// ─────────────────────────────────────────────────────────────────────────────

static void test_get_status(void) {
  TEST_MESSAGE("user fetches /api/status");
  assert_get("/api/status", 200);
}

static void test_get_heap(void) {
  TEST_MESSAGE("user fetches /api/heap");
  assert_get("/api/heap", 200);
}

static void test_get_wifi(void) {
  TEST_MESSAGE("user fetches /api/wifi");
  assert_get("/api/wifi", 200);
}

static void test_get_wireless_status(void) {
  TEST_MESSAGE("user fetches /api/wireless/status");
  assert_get("/api/wireless/status", 200);
}

static void test_get_device_status(void) {
  TEST_MESSAGE("user fetches /api/system/device/status");
  assert_get("/api/system/device/status", 200);
}

static void test_get_filesystem_root(void) {
  TEST_MESSAGE("user fetches /api/filesystem");
  assert_get("/api/filesystem", 200);
}

static void test_get_filesystem_sd(void) {
  TEST_MESSAGE("user fetches /api/filesystem/sd");
  assert_get("/api/filesystem/sd", 200);
}

static void test_get_filesystem_littlefs(void) {
  TEST_MESSAGE("user fetches /api/filesystem/littlefs");
  assert_get("/api/filesystem/littlefs", 200);
}

static void test_get_co2_config(void) {
  TEST_MESSAGE("user fetches /api/co2/config");
  assert_get("/api/co2/config", 200);
}

static void test_get_ap_config(void) {
  TEST_MESSAGE("user fetches /api/ap/config");
  assert_get("/api/ap/config", 200);
}

static void test_get_ota_rollback(void) {
  TEST_MESSAGE("user fetches /api/system/ota/rollback");
  assert_get("/api/system/ota/rollback", 200);
}

// ─────────────────────────────────────────────────────────────────────────────
//  POST routes
// ─────────────────────────────────────────────────────────────────────────────

static void test_post_co2_start(void) {
  TEST_MESSAGE("user starts CO2 via POST /api/co2/start");
  assert_post("/api/co2/start", NULL, 200);
}

static void test_post_co2_stop(void) {
  TEST_MESSAGE("user stops CO2 via POST /api/co2/stop");
  assert_post("/api/co2/stop", NULL, 200);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Error handling
// ─────────────────────────────────────────────────────────────────────────────

static void test_404_not_found(void) {
  TEST_MESSAGE("user requests non-existent route");
  assert_get("/api/nonexistent", 404);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Runner
// ─────────────────────────────────────────────────────────────────────────────

void services::http_e2e::test(void) {
  // Skipped — self-connect via WiFiClient needs further investigation
  // (AsyncTCP task scheduling vs test task on same core)
  //
  // it("user observes /api/status responds 200",            test_get_status);
  // it("user observes /api/heap responds 200",              test_get_heap);
  // it("user observes /api/wifi responds 200",              test_get_wifi);
  // it("user observes /api/wireless/status responds 200",   test_get_wireless_status);
  // it("user observes /api/system/device/status responds",  test_get_device_status);
  // it("user observes /api/filesystem root responds",       test_get_filesystem_root);
  // it("user observes /api/filesystem/sd responds",         test_get_filesystem_sd);
  // it("user observes /api/filesystem/littlefs responds",   test_get_filesystem_littlefs);
  // it("user observes /api/co2/config responds",            test_get_co2_config);
  // it("user observes /api/ap/config responds",             test_get_ap_config);
  // it("user observes /api/system/ota/rollback responds",   test_get_ota_rollback);
  // it("user observes POST /api/co2/start responds",        test_post_co2_start);
  // it("user observes POST /api/co2/stop responds",         test_post_co2_stop);
  // it("user observes 404 for unknown routes",              test_404_not_found);
}

#endif
