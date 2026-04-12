#include "networking.h"
#include "../../../config.h"
#include "../../../networking/wifi.h"

#include <Arduino.h>
#include <WiFi.h>
#include <AsyncJson.h>
#include <ArduinoJson.h>

namespace {

const char *wifi_encryption_string(wifi_auth_mode_t auth) {
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

void fill_wireless_status(JsonObject &data) {
  bool station_connected = WiFi.isConnected();
  data["connected"] = station_connected;
  data["mode"] = ::networking::wifi::ap::isActive() ? "ap_sta" : "sta";
  data["tenant"] = config::cloudevents::TENANT;
  data["sta_ssid"] = station_connected ? WiFi.SSID() : "";
  data["sta_bssid"] = station_connected ? WiFi.BSSIDstr() : "";
  data["sta_ipv4"] = station_connected ? WiFi.localIP().toString() : "0.0.0.0";
  data["wifi_rssi"] = station_connected ? WiFi.RSSI() : 0;
  data["ap_active"] = ::networking::wifi::ap::isActive();
  data["ap_ssid"] = ::networking::wifi::ap::isActive() ? WiFi.softAPSSID() : "";
  data["ap_ipv4"] = ::networking::wifi::ap::isActive() ? WiFi.softAPIP().toString() : "0.0.0.0";
  data["ap_clients"] = ::networking::wifi::ap::isActive() ? WiFi.softAPgetStationNum() : 0;
  data["ap_hostname"] = ::networking::wifi::ap::isActive() ? WiFi.softAPgetHostname() : "";
  data["ap_mac"] = ::networking::wifi::ap::isActive() ? WiFi.softAPmacAddress() : "";
}

void handle_wifi(AsyncWebServerRequest *request) {
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();

  root["connected"] = WiFi.isConnected();
  root["ssid"] = WiFi.SSID();
  root["ip"] = WiFi.localIP().toString();
  root["rssi"] = WiFi.RSSI();
  root["mac"] = WiFi.macAddress();

  response->setLength();
  request->send(response);
}

void handle_wireless_status(AsyncWebServerRequest *request) {
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = true;
  JsonObject data = root["data"].to<JsonObject>();
  fill_wireless_status(data);
  response->setLength();
  request->send(response);
}

void handle_wireless_scan(AsyncWebServerRequest *request) {
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
    network["ssid"] = WiFi.SSID(index);
    network["bssid"] = WiFi.BSSIDstr(index);
    network["rssi"] = WiFi.RSSI(index);
    network["channel"] = WiFi.channel(index);
    network["encryption"] = wifi_encryption_string(WiFi.encryptionType(index));
    network["open"] = (WiFi.encryptionType(index) == WIFI_AUTH_OPEN);
  }

  WiFi.scanDelete();
  response->setLength();
  request->send(response);
}

void handle_ap_config_get(AsyncWebServerRequest *request) {
  APConfig ap_config = {};
  networking::wifi::ap::accessConfig(&ap_config);

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = true;
  JsonObject data = root["data"].to<JsonObject>();
  data["ssid"] = ap_config.ssid;
  data["enabled"] = networking::wifi::ap::isActive();
  data["active"] = networking::wifi::ap::isActive();
  data["ip"] = networking::wifi::ap::isActive() ? WiFi.softAPIP().toString() : "0.0.0.0";
  data["clients"] = networking::wifi::ap::isActive() ? WiFi.softAPgetStationNum() : 0;
  data["hostname"] = networking::wifi::ap::isActive() ? WiFi.softAPgetHostname() : "";
  data["mac"] = networking::wifi::ap::isActive() ? WiFi.softAPmacAddress() : "";
  response->setLength();
  request->send(response);
}

}

void services::http::api::networking::registerRoutes(AsyncWebServer &server,
                                                     AsyncRateLimitMiddleware &scan_limit) {
  server.on("/api/wifi", HTTP_GET, handle_wifi);
  server.on("/api/wireless/status", HTTP_GET, handle_wireless_status);
  server.on("/api/wireless/actions/scan", HTTP_POST, handle_wireless_scan)
    .addMiddleware(&scan_limit);
  server.on("/api/ap/config", HTTP_GET, handle_ap_config_get);

  AsyncCallbackJsonWebHandler &ap_config_handler =
      server.on("/api/ap/config", HTTP_POST,
          [](AsyncWebServerRequest *request, JsonVariant &json) {
    JsonObject body = json.as<JsonObject>();

    if (!body["ssid"].isNull() && !body["password"].isNull()) {
      const char *ssid = body["ssid"] | "";
      const char *password = body["password"] | "";
      ::networking::wifi::ap::configure(ssid, password);

      if (::networking::wifi::ap::isActive()) {
        ::networking::wifi::ap::disable();
        ::networking::wifi::ap::enable();
      }
    }

    if (!body["enabled"].isNull()) {
      bool enabled = body["enabled"] | true;
      if (enabled) ::networking::wifi::ap::enable();
      else ::networking::wifi::ap::disable();
    }

    APConfig ap_config = {};
    ::networking::wifi::ap::accessConfig(&ap_config);

    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = true;
    JsonObject data = root["data"].to<JsonObject>();
    data["ssid"] = ap_config.ssid;
    data["enabled"] = ::networking::wifi::ap::isActive();
    data["active"] = ::networking::wifi::ap::isActive();
    data["ip"] = ::networking::wifi::ap::isActive() ? WiFi.softAPIP().toString() : "0.0.0.0";
    data["clients"] = ::networking::wifi::ap::isActive() ? WiFi.softAPgetStationNum() : 0;
    response->setLength();
    request->send(response);
  });
  ap_config_handler.setMaxContentLength(512);

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
      ::networking::wifi::ap::enable();
    }

    response->setLength();
    request->send(response);
  });
  connect_handler.setMaxContentLength(512);
}
