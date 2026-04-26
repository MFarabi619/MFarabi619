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

const char *tunnel_provider_label(::networking::tunnel::Provider provider) {
  switch (provider) {
    case ::networking::tunnel::ProviderBore:
      return "bore";
    case ::networking::tunnel::ProviderSelfHosted:
      return "self-hosted";
    case ::networking::tunnel::ProviderLocaltunnel:
      return "localtunnel";
    default:
      return "disabled";
  }
}

bool parse_tunnel_provider(const String &provider, ::networking::tunnel::Provider *parsed_provider) {
  if (!parsed_provider) return false;
  if (provider == "bore") {
    *parsed_provider = ::networking::tunnel::ProviderBore;
    return true;
  }
  if (provider == "self-hosted") {
    *parsed_provider = ::networking::tunnel::ProviderSelfHosted;
    return true;
  }
  if (provider == "localtunnel") {
    *parsed_provider = ::networking::tunnel::ProviderLocaltunnel;
    return true;
  }
  if (provider == "disabled") {
    *parsed_provider = ::networking::tunnel::ProviderDisabled;
    return true;
  }
  return false;
}

void fill_tunnel_config(JsonObject &data, const ::networking::tunnel::Config &config) {
  data["enabled"] = config.enabled;
  data["provider"] = tunnel_provider_label(config.provider);
  data["host"] = config.host;
  data["path"] = config.path;
  data["local_port"] = config.local_port;
  data["reconnect"] = config.reconnect;
}

void fill_tunnel_status(JsonObject &data) {
  ::networking::tunnel::Config config = {};
  ::networking::tunnel::Snapshot snapshot = {};
  ::networking::tunnel::accessConfig(config);
  ::networking::tunnel::accessSnapshot(snapshot);

  JsonObject config_data = data["config"].to<JsonObject>();
  fill_tunnel_config(config_data, config);
  JsonObject runtime = data["runtime"].to<JsonObject>();
  runtime["enabled"] = snapshot.enabled;
  runtime["started"] = snapshot.started;
  runtime["stopped"] = snapshot.stopped;
  runtime["ready"] = snapshot.ready;
  runtime["provider"] = ::networking::tunnel::accessProviderName();
  runtime["phase"] = (int)snapshot.phase;
  runtime["url"] = snapshot.url;
  runtime["remote_port"] = snapshot.remote_port;
  runtime["last_client_ip"] = ::networking::tunnel::accessLastClientIP();
  runtime["connect_attempts"] = snapshot.connect_attempts;
  runtime["backoff_ms"] = snapshot.backoff_ms;
  runtime["last_error_at"] = snapshot.last_error_at;
  runtime["last_error"] = snapshot.last_error;
}

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
    JsonObject data = root["data"].to<JsonObject>();
    fill_tunnel_status(data);
    response->setLength();
    request->send(response);
  });
  server.on("/api/tunnel/config", HTTP_GET, [](AsyncWebServerRequest *request) {
    ::networking::tunnel::Config config = {};
    ::networking::tunnel::accessConfig(config);

    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = true;
    JsonObject data = root["data"].to<JsonObject>();
    fill_tunnel_config(data, config);
    response->setLength();
    request->send(response);
  });
  AsyncCallbackJsonWebHandler &tunnel_config_handler =
      server.on("/api/tunnel/config", HTTP_POST,
          [](AsyncWebServerRequest *request, JsonVariant &json) {
    ::networking::tunnel::Config config = {};
    ::networking::tunnel::accessConfig(config);

    JsonObject body = json.as<JsonObject>();
    if (!body["enabled"].isNull()) {
      config.enabled = body["enabled"] | config.enabled;
    }
    if (!body["provider"].isNull()) {
      String provider = body["provider"] | "";
      ::networking::tunnel::Provider parsed_provider = config.provider;
      if (parse_tunnel_provider(provider, &parsed_provider)) {
        config.provider = parsed_provider;
      }
    }
    if (!body["host"].isNull()) {
      strlcpy(config.host, body["host"] | "", sizeof(config.host));
    }
    if (!body["path"].isNull()) {
      strlcpy(config.path, body["path"] | "", sizeof(config.path));
    }
    if (!body["local_port"].isNull()) {
      config.local_port = body["local_port"] | config.local_port;
    }
    if (!body["reconnect"].isNull()) {
      config.reconnect = body["reconnect"] | config.reconnect;
    }

    bool stored = ::networking::tunnel::storeConfig(&config);
    if (stored) {
      ::networking::tunnel::configure(config);
    }

    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = stored;
    JsonObject data = root["data"].to<JsonObject>();
    fill_tunnel_status(data);
    response->setLength();
    request->send(response);
  });
  tunnel_config_handler.setMaxContentLength(512);
  server.on("/api/tunnel/actions/enable", HTTP_POST, [](AsyncWebServerRequest *request) {
    ::networking::tunnel::Config config = {};
    ::networking::tunnel::accessConfig(config);
    config.enabled = true;
    bool stored = ::networking::tunnel::storeConfig(&config);
    if (stored) {
      ::networking::tunnel::enable();
    }

    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = stored;
    JsonObject data = root["data"].to<JsonObject>();
    fill_tunnel_status(data);
    response->setLength();
    request->send(response);
  });
  server.on("/api/tunnel/actions/disable", HTTP_POST, [](AsyncWebServerRequest *request) {
    ::networking::tunnel::Config config = {};
    ::networking::tunnel::accessConfig(config);
    config.enabled = false;
    bool stored = ::networking::tunnel::storeConfig(&config);
    if (stored) {
      ::networking::tunnel::disable();
    }

    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = stored;
    JsonObject data = root["data"].to<JsonObject>();
    fill_tunnel_status(data);
    response->setLength();
    request->send(response);
  });
  server.on("/api/tunnel/actions/restart", HTTP_POST, [](AsyncWebServerRequest *request) {
    ::networking::tunnel::Config config = {};
    ::networking::tunnel::accessConfig(config);
    ::networking::tunnel::stop();
    if (config.enabled) {
      ::networking::tunnel::initialize();
    }

    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = true;
    JsonObject data = root["data"].to<JsonObject>();
    fill_tunnel_status(data);
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
