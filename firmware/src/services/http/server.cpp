#include "../http.h"
#include "../cloudevents.h"
#include "../ws_shell.h"
#include "api/email.h"
#include "api/filesystem.h"
#include "api/networking.h"
#include "api/sensors.h"
#include "api/system.h"
#include "../../config.h"

#include <Arduino.h>
#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include <LittleFS.h>
#include <SD.h>

namespace {

AsyncWebServer server(config::http::PORT);

AsyncCorsMiddleware cors;
AsyncLoggingMiddleware logging;
AsyncAuthenticationMiddleware auth;
AsyncRateLimitMiddleware scan_limit;
AsyncRateLimitMiddleware reset_limit;
AsyncRateLimitMiddleware ota_limit;
AsyncRateLimitMiddleware format_limit;

bool sd_ready = false;

bool ensure_sd(void) {
  if (sd_ready) return true;
  sd_ready = SD.begin();
  return sd_ready;
}

bool requires_admin_auth(AsyncWebServerRequest *request) {
  if (!request || request->method() == HTTP_OPTIONS) return false;

  String url = request->url();
  if (url == "/ws/shell") return true;
  if (!url.startsWith("/api/")) return false;

  return !(url == "/api/wifi"
      || url == "/api/system/device/status"
      || url == "/api/cloudevents"
      || url == "/api/wireless/status");
}

class CaptivePortalRedirectHandler : public AsyncWebHandler {
public:
  bool canHandle(AsyncWebServerRequest *request) const override {
    return request != nullptr;
  }

  void handleRequest(AsyncWebServerRequest *request) override {
    if (ensure_sd() && SD.exists("/index.html")) {
      request->send(SD, "/index.html", "text/html");
      return;
    }
    request->redirect("http://" + WiFi.softAPIP().toString() + "/");
  }
};

}

AsyncEventSource http_events("/events");

void services::http::service() {
  // no-op: async handlers removed
}

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
    request->requestAuthentication(AsyncAuthType::AUTH_DIGEST,
                                   config::http::AUTH_REALM);
  });
#endif

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

  services::http::api::system::registerRoutes(server, reset_limit, ota_limit);
  services::http::api::filesystem::registerRoutes(server, format_limit);
  services::http::api::networking::registerRoutes(server, scan_limit);
  services::http::api::sensors::registerRoutes(server);
  services::http::api::email::registerRoutes(server);

  services::cloudevents::registerRoutes(&server);
  services::ws_shell::registerRoutes(&server);

  server.serveStatic("/", LittleFS, "/www/")
    .setDefaultFile("index.html")
    .setCacheControl("max-age=3600");

  server.addHandler(new CaptivePortalRedirectHandler()).setFilter(ON_AP_FILTER);

  server.onNotFound([](AsyncWebServerRequest *request) {
    String url = request->url();

    if (url == "/" && ensure_sd() && SD.exists("/index.html")) {
      request->send(SD, "/index.html", "text/html");
      return;
    }

    request->send(404, "application/json", "{\"error\":\"not found\"}");
  });

  server.begin();
  Serial.printf("[http] listening on port %d\n", config::http::PORT);
}
