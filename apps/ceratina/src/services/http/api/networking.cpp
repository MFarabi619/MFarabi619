#include "api.h"
#include <config.h>
#include <networking/wifi.h>
#include <identity.h>
#include "networking/tunnel.h"

#include <Arduino.h>
#include <WiFi.h>
#include <AsyncJson.h>
#include <ArduinoJson.h>

namespace {

void fill_wireless_status(JsonObject &data) {
  NetworkStatusSnapshot snapshot = {};
  ::networking::wifi::accessSnapshot(&snapshot);
  data["connected"] = snapshot.connected;
  data["mode"] = snapshot.ap.active ? "ap_sta" : "sta";
  data["tenant"] = config::cloudevents::TENANT;
  data["sta_ssid"] = snapshot.ssid;
  data["sta_bssid"] = snapshot.bssid;
  data["sta_ipv4"] = snapshot.ip;
  data["wifi_rssi"] = snapshot.rssi;
  data["ap_active"] = snapshot.ap.active;
  data["ap_ssid"] = snapshot.ap.ssid;
  data["ap_ipv4"] = snapshot.ap.ip;
  data["ap_clients"] = snapshot.ap.clients;
  data["ap_hostname"] = snapshot.ap.hostname;
  data["ap_mac"] = snapshot.ap.mac;
}

void handle_wifi(AsyncWebServerRequest *request) {
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();

  NetworkStatusSnapshot snapshot = {};
  ::networking::wifi::accessSnapshot(&snapshot);
  root["connected"] = snapshot.connected;
  root["ssid"] = snapshot.ssid;
  root["ip"] = snapshot.ip;
  root["rssi"] = snapshot.rssi;
  root["mac"] = snapshot.mac;

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
    WifiScanResult results[16] = {};
    WifiScanCommand command = {
      .results = results,
      .max_results = 16,
      .result_count = -1,
    };
    ::networking::wifi::scan(&command);
    int16_t count = command.result_count;

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = (count >= 0);
  JsonObject data = root["data"].to<JsonObject>();
  data["scan_count"] = (count >= 0) ? count : 0;

  JsonArray networks = data["networks"].to<JsonArray>();
  int16_t limit = (count < 16) ? count : 16;
  for (int16_t index = 0; index < limit; index++) {
    JsonObject network = networks.add<JsonObject>();
    network["ssid"] = results[index].ssid;
    network["bssid"] = results[index].bssid;
    network["rssi"] = results[index].rssi;
    network["channel"] = results[index].channel;
    network["encryption"] = results[index].encryption;
    network["open"] = results[index].open;
  }
  response->setLength();
  request->send(response);
}

void handle_ap_config_get(AsyncWebServerRequest *request) {
  APSnapshot snapshot = {};
  ::networking::wifi::ap::accessSnapshot(&snapshot);

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = true;
  JsonObject data = root["data"].to<JsonObject>();
  data["ssid"] = snapshot.ssid;
  data["enabled"] = snapshot.active;
  data["active"] = snapshot.active;
  data["ip"] = snapshot.ip;
  data["clients"] = snapshot.clients;
  data["hostname"] = snapshot.hostname;
  data["mac"] = snapshot.mac;
  response->setLength();
  request->send(response);
}

}

void services::http::api::networking::registerRoutes(AsyncWebServer &server,
                                                     AsyncRateLimitMiddleware &scan_limit) {
  server.on("/api/wifi", HTTP_GET, handle_wifi);
  server.on("/api/wireless/config", HTTP_DELETE, [](AsyncWebServerRequest *request) {
    bool ok = ::networking::wifi::clearConfig();
    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = ok;
    response->setLength();
    request->send(response);
  });
  server.on("/api/tunnel/status", HTTP_GET, [](AsyncWebServerRequest *request) {
    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = true;
    root["enabled"] = (bool)CERATINA_TUNNEL_ENABLED;
    root["ready"] = ::networking::tunnel::isReady();
    root["url"] = ::networking::tunnel::accessURL();
    response->setLength();
    request->send(response);
  });
  server.on("/api/wireless/status", HTTP_GET, handle_wireless_status);
  server.on("/api/wireless/actions/scan", HTTP_POST, handle_wireless_scan)
    .addMiddleware(&scan_limit);
  server.on("/api/ap/config", HTTP_GET, handle_ap_config_get);

  AsyncCallbackJsonWebHandler &ap_config_handler =
      server.on("/api/ap/config", HTTP_POST,
          [](AsyncWebServerRequest *request, JsonVariant &json) {
    JsonObject body = json.as<JsonObject>();

    if (!body["ssid"].isNull() && !body["password"].isNull()) {
      APConfigureCommand command = {
        .config = {},
        .snapshot = {},
      };
      strlcpy(command.config.ssid, body["ssid"] | "", sizeof(command.config.ssid));
      strlcpy(command.config.password, body["password"] | "", sizeof(command.config.password));
      ::networking::wifi::ap::applyConfig(&command);
    }

    if (!body["enabled"].isNull()) {
      APEnabledCommand command = {
        .enabled = body["enabled"] | true,
        .snapshot = {},
      };
      ::networking::wifi::ap::setEnabled(&command);
    }

    APSnapshot snapshot = {};
    ::networking::wifi::ap::accessSnapshot(&snapshot);

    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = true;
    JsonObject data = root["data"].to<JsonObject>();
    data["ssid"] = snapshot.ssid;
    data["enabled"] = snapshot.active;
    data["active"] = snapshot.active;
    data["ip"] = snapshot.ip;
    data["clients"] = snapshot.clients;
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
    String identity = body["identity"] | "";
    String username = body["username"] | "";
    bool is_enterprise = body["is_enterprise"] | false;
    ssid.trim();

    if (ssid.isEmpty()) {
      request->send(400, asyncsrv::T_application_json,
                    "{\"ok\":false,\"error\":{\"code\":\"SSID_REQUIRED\","
                    "\"message\":\"Missing ssid parameter\"}}");
      return;
    }

    WifiConnectCommand command = {
      .request = {
        .ssid = ssid.c_str(),
        .password = password.c_str(),
        .identity = is_enterprise ? identity.c_str() : nullptr,
        .username = is_enterprise ? username.c_str() : nullptr,
        .is_enterprise = is_enterprise,
        .enable_ap_fallback = true,
      },
      .result = {},
    };
    ::networking::wifi::connect(&command);

    if (command.result.connected) {
      WifiSavedConfig saved = {};
      strlcpy(saved.ssid, ssid.c_str(), sizeof(saved.ssid));
      strlcpy(saved.password, password.c_str(), sizeof(saved.password));
      if (is_enterprise) {
        strlcpy(saved.identity, identity.c_str(), sizeof(saved.identity));
        strlcpy(saved.username, username.c_str(), sizeof(saved.username));
        saved.is_enterprise = true;
      }
      ::networking::wifi::storeConfig(&saved);
    }

    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = command.result.connected;
    JsonObject data = root["data"].to<JsonObject>();
    data["attempted_ssid"] = ssid;
    data["is_enterprise"] = is_enterprise;
    data["status_code"] = command.result.status_code;
    fill_wireless_status(data);

    response->setLength();
    request->send(response);
  });
  connect_handler.setMaxContentLength(512);
}
