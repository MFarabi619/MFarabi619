#include "api.h"
#include "services/email.h"
#include <config.h>

#include <ArduinoJson.h>

void services::http::api::email::registerRoutes(AsyncWebServer &server) {
#if CERATINA_SMTP_ENABLED
  server.on("/api/smtp/config", HTTP_GET,
            [](AsyncWebServerRequest *request) {
    char host[128] = {0};
    uint16_t port = 0;
    bool ok = ::services::email::accessEndpoint(host, sizeof(host), &port);

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
    request->send(200, asyncsrv::T_application_json, json);
  });

  server.on("/api/smtp/send", HTTP_POST,
            [](AsyncWebServerRequest *request) {
    char host[128] = {0};
    uint16_t port = 0;
    if (!::services::email::accessEndpoint(host, sizeof(host), &port)) {
      request->send(400, asyncsrv::T_application_json,
                    "{\"ok\":false,\"error\":\"SMTP not configured\"}");
      return;
    }

    bool sent = ::services::email::sendTest();
    JsonDocument doc;
    doc["ok"] = sent;
    JsonObject data = doc["data"].to<JsonObject>();
    data["smtp_host"] = host;
    data["smtp_port"] = port;
    data["sent"] = sent;

    String json;
    serializeJson(doc, json);
    request->send(sent ? 200 : 500, asyncsrv::T_application_json, json);
  });
#else
  (void)server;
#endif
}
