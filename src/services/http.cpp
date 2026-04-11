#include "http.h"
#include "cloudevents.h"
#include "co2.h"
#include "smtp.h"
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

static AsyncWebServer server(CONFIG_HTTP_PORT);
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

struct UploadContext {
  bool ok = false;
};

static bool is_sensitive_path(const String &path) {
  return path == "/.ssh" || path.startsWith("/.ssh/")
      || path == CONFIG_SSH_HOSTKEY_PATH;
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

struct FsRef {
  fs::FS *fs;
  String path;
  bool ok;
};

static FsRef fs_resolve(const String &url) {
  const char *prefix = "/api/filesystem/";
  String remainder = url.substring(strlen(prefix));

  if (remainder.startsWith("sd")) {
    String path = remainder.substring(2);
    if (path.isEmpty()) path = "/";
    if (SD.begin(CONFIG_SD_CS_GPIO))
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

static bool fs_ensure_parents(fs::FS &fs, const String &path) {
  int last_slash = path.lastIndexOf('/');
  if (last_slash <= 0) return true;

  String dir = path.substring(0, last_slash);
  for (int i = 1; i <= (int)dir.length(); i++) {
    if (i == (int)dir.length() || dir[i] == '/') {
      String partial = dir.substring(0, i);
      if (!fs.exists(partial)) {
        if (!fs.mkdir(partial)) return false;
      }
    }
  }
  return true;
}

class CaptivePortalHandler : public AsyncWebHandler {
public:
  bool canHandle(AsyncWebServerRequest *request) const override {
    return request != nullptr;
  }

  void handleRequest(AsyncWebServerRequest *request) override {
    if (SD.begin(CONFIG_SD_CS_GPIO) && SD.exists("/index.html")) {
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
  if (SD.begin(CONFIG_SD_CS_GPIO))
    fs_list_dir(SD, "/", sd_arr);

  JsonArray lfs_arr = root["littlefs"].to<JsonArray>();
  fs_list_dir(LittleFS, "/", lfs_arr);

  response->setLength();
  request->send(response);
}

static void api_fs_get(AsyncWebServerRequest *request) {
  FsRef ref = fs_resolve(request->url());
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
  FsRef ref = fs_resolve(request->url());
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
  UploadContext *ctx = reinterpret_cast<UploadContext *>(request->_tempObject);

  if (!index) {
    delete ctx;
    ctx = new UploadContext();
    request->_tempObject = ctx;

    FsRef ref = fs_resolve(request->url());
    if (!ref.ok) {
      request->send(400, "application/json", "{\"ok\":false,\"error\":\"invalid filesystem prefix\"}");
      return;
    }
    if (is_sensitive_path(ref.path)) {
      request->send(403, "application/json", "{\"ok\":false,\"error\":\"forbidden path\"}");
      return;
    }

    if (!fs_ensure_parents(*ref.fs, ref.path)) {
      request->send(500, "application/json", "{\"ok\":false,\"error\":\"mkdir -p failed\"}");
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
  std::unique_ptr<UploadContext> ctx(
      reinterpret_cast<UploadContext *>(request->_tempObject));
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
  FsRef ref = fs_resolve(request->url());
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
  co2_get_config(&config);

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = co2_is_available();
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
  bool ok = co2_start();
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = ok;
  response->setLength();
  request->send(response);
}

static void api_co2_stop(AsyncWebServerRequest *request) {
  bool ok = co2_stop();
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
  data["clients"] = wifi_is_ap_active() ? WiFi.softAPgetStationNum() : 0;
  data["hostname"] = wifi_is_ap_active() ? WiFi.softAPgetHostname() : "";
  data["mac"] = wifi_is_ap_active() ? WiFi.softAPmacAddress() : "";
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
  data["sta_bssid"]  = wifi_is_connected() ? WiFi.BSSIDstr() : "";
  data["sta_ipv4"]   = wifi_is_connected() ? WiFi.localIP().toString() : "0.0.0.0";
  data["wifi_rssi"]  = wifi_is_connected() ? WiFi.RSSI() : 0;
  data["ap_active"]  = wifi_is_ap_active();
  data["ap_ssid"]    = wifi_is_ap_active() ? WiFi.softAPSSID() : "";
  data["ap_ipv4"]    = wifi_is_ap_active() ? WiFi.softAPIP().toString() : "0.0.0.0";
  data["ap_clients"] = wifi_is_ap_active() ? WiFi.softAPgetStationNum() : 0;
  data["ap_hostname"] = wifi_is_ap_active() ? WiFi.softAPgetHostname() : "";
  data["ap_mac"] = wifi_is_ap_active() ? WiFi.softAPmacAddress() : "";
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

void http_server_service(void) {
  // no-op: async handlers removed
}

// ─────────────────────────────────────────────────────────────────────────────
//  Captive Portal
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
//  Server Init
// ─────────────────────────────────────────────────────────────────────────────

void http_server_start(void) {
  cors.setOrigin("*");
  cors.setMethods("GET, POST, PUT, PATCH, DELETE, OPTIONS");
  cors.setHeaders("Content-Type, Authorization");
  server.addMiddleware(&cors);

#if CONFIG_HTTP_AUTH_ENABLED
  auth.setUsername(CONFIG_HTTP_AUTH_USER);
  auth.setPassword(CONFIG_HTTP_AUTH_PASSWORD);
  auth.setRealm(CONFIG_HTTP_AUTH_REALM);
  auth.setAuthType(AsyncAuthType::AUTH_DIGEST);
  auth.generateHash();
  server.addMiddleware([](AsyncWebServerRequest *request, ArMiddlewareNext next) {
    if (!requires_admin_auth(request)) { next(); return; }
    if (auth.allowed(request)) { next(); return; }
    request->requestAuthentication(AsyncAuthType::AUTH_DIGEST, CONFIG_HTTP_AUTH_REALM);
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

  WiFi.setScanTimeout(CONFIG_WIFI_TIMEOUT_MS);

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
    FsRef ref = fs_resolve(request->url());
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
    root["can_rollback"] = update_can_rollback();
    response->setLength();
    request->send(response);
  });

  server.on("/api/system/ota/rollback", HTTP_POST,
            [](AsyncWebServerRequest *request) {
    bool ok = update_rollback();
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
      bool ok = update_from_url(u->c_str());
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
    bool ok = update_from_sd();
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
      co2_set_measurement_interval(body["measurement_interval_seconds"]);
    if (!body["auto_calibration_enabled"].isNull())
      co2_set_auto_calibration(body["auto_calibration_enabled"]);
    if (!body["temperature_offset_celsius"].isNull())
      co2_set_temperature_offset(body["temperature_offset_celsius"]);
    if (!body["altitude_meters"].isNull())
      co2_set_altitude(body["altitude_meters"]);
    if (!body["forced_recalibration_ppm"].isNull())
      co2_force_recalibration(body["forced_recalibration_ppm"]);

    Co2Config config = {};
    co2_get_config(&config);
    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = co2_is_available();
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
      wifi_set_ap_config(ssid, password);

      // Restart AP with new config if currently active
      if (wifi_is_ap_active()) {
        wifi_stop_ap();
        wifi_start_ap();
      }
    }

    if (!body["enabled"].isNull()) {
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
    data["clients"] = wifi_is_ap_active() ? WiFi.softAPgetStationNum() : 0;
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

    wifi_set_credentials(ssid.c_str(), password.c_str());

    WiFi.disconnect(false, false);
    WiFi.mode(WIFI_MODE_STA);
    WiFi.setHostname(CONFIG_HOSTNAME);
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
  connect_handler.setMaxContentLength(512);

#if CONFIG_SMTP_ENABLED
  server.on("/api/smtp/config", HTTP_GET,
            [](AsyncWebServerRequest *request) {
    char host[128] = {0};
    uint16_t port = 0;
    bool ok = smtp_get_endpoint(host, sizeof(host), &port);

    JsonDocument doc;
    doc["ok"] = ok;
    JsonObject data = doc["data"].to<JsonObject>();
    data["smtp_enabled"] = true;
    data["smtp_test_enabled"] = CONFIG_SMTP_TEST_ENABLED == 1;
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
    if (!smtp_get_endpoint(host, sizeof(host), &port)) {
      request->send(400, "application/json",
                    "{\"ok\":false,\"error\":\"SMTP not configured\"}");
      return;
    }

    bool sent = smtp_send_test_email();
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

  cloudevents_register_routes(&server);
  ws_shell_register(&server);

  server.serveStatic("/", LittleFS, "/www/")
    .setDefaultFile("index.html")
    .setCacheControl("max-age=3600");

  server.addHandler(new CaptivePortalHandler()).setFilter(ON_AP_FILTER);

  server.onNotFound([](AsyncWebServerRequest *request) {
    String url = request->url();

    if (url == "/" && SD.begin(CONFIG_SD_CS_GPIO) && SD.exists("/index.html")) {
      request->send(SD, "/index.html", "text/html");
      return;
    }

    request->send(404, "application/json", "{\"error\":\"not found\"}");
  });

  server.begin();
  Serial.printf("[http] listening on port %d\n", CONFIG_HTTP_PORT);
}
