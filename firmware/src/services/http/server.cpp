#include "../http.h"
#include "../cloudevents.h"
#include "../ws_shell.h"
#include "../../hardware/storage.h"
#include "../../networking/wifi.h"
#include "api/database.h"
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

bool sd_has_index() {
  if (!hardware::storage::ensureSD()) return false;
  return SD.exists("/index.html") || SD.exists("/index.html.gz");
}

void send_index_from_sd(AsyncWebServerRequest *request) {
  if (SD.exists("/index.html.gz")) {
    AsyncWebServerResponse *response = request->beginResponse(SD, "/index.html.gz", "text/html; charset=utf-8");
    response->addHeader("Content-Encoding", "gzip");
    request->send(response);
  } else {
    request->send(SD, "/index.html", "text/html; charset=utf-8");
  }
}

void captive_portal_redirect(AsyncWebServerRequest *request) {
  String location = "http://" + WiFi.softAPIP().toString() + "/";
  AsyncWebServerResponse *response = request->beginResponse(302);
  response->addHeader("Location", location);
  response->addHeader("Cache-Control", "no-store, no-cache, must-revalidate");
  response->addHeader("Pragma", "no-cache");
  request->send(response);
}

void send_portal_page(AsyncWebServerRequest *request) {
  if (sd_has_index()) {
    send_index_from_sd(request);
    return;
  }
  request->send(200, "text/html; charset=utf-8",
    "<!DOCTYPE html><html><head><title>Ceratina</title></head><body>"
    "<h1>Ceratina</h1><p>Portal UI unavailable (index.html missing on SD).</p>"
    "</body></html>");
}

class CaptivePortalRedirectHandler : public AsyncWebHandler {
public:
  bool canHandle(AsyncWebServerRequest *request) const override {
    if (!request || !request->hasHeader("Host")) return true;
    const AsyncWebHeader *host = request->getHeader("Host");
    if (!host) return true;
    String h = host->value();
    h.toLowerCase();
    String ap_ip = WiFi.softAPIP().toString();
    if (h == ap_ip || h.startsWith(ap_ip + ":")) return false;
    if (h.startsWith("ceratina")) return false;
    return true;
  }

  void handleRequest(AsyncWebServerRequest *request) override {
    captive_portal_redirect(request);
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
  services::http::api::database::registerRoutes(server);
  services::http::api::email::registerRoutes(server);

  services::cloudevents::registerRoutes(&server);
  services::ws_shell::registerRoutes(&server);

  hardware::storage::ensureSD();
  server.serveStatic("/", SD, "/")
    .setDefaultFile("index.html")
    .setCacheControl("public, max-age=86400")
    .setTryGzipFirst(true);

  server.on("/portal", HTTP_GET, send_portal_page);
  server.on(AsyncURIMatcher::exact("/generate_204"), HTTP_GET, captive_portal_redirect);
  server.on(AsyncURIMatcher::exact("/gen_204"), HTTP_GET, captive_portal_redirect);
  server.on(AsyncURIMatcher::exact("/fwlink"), HTTP_GET, captive_portal_redirect);
  server.on(AsyncURIMatcher::exact("/redirect"), HTTP_GET, captive_portal_redirect);
  server.on(AsyncURIMatcher::exact("/hotspot-detect.html"), HTTP_GET, captive_portal_redirect);
  server.on(AsyncURIMatcher::exact("/canonical.html"), HTTP_GET, captive_portal_redirect);
  server.on(AsyncURIMatcher::exact("/mobile/status.php"), HTTP_GET, captive_portal_redirect);
  server.on(AsyncURIMatcher::exact("/connecttest.txt"), HTTP_GET, captive_portal_redirect);
  server.on(AsyncURIMatcher::exact("/ncsi.txt"), HTTP_GET, captive_portal_redirect);
  server.on(AsyncURIMatcher::exact("/success.txt"), HTTP_GET, captive_portal_redirect);

  server.addHandler(new CaptivePortalRedirectHandler()).setFilter(ON_AP_FILTER);

  server.onNotFound([](AsyncWebServerRequest *request) {
    if (sd_has_index()) {
      send_index_from_sd(request);
      return;
    }

    request->send(404, "application/json", "{\"error\":\"not found\"}");
  });

  server.begin();
  Serial.printf("[http] listening on port %d\n", config::http::PORT);
}
