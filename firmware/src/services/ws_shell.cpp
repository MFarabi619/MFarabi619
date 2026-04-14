#include "ws_shell.h"
#include "../config.h"
#include "../console/remote.h"

#include <Arduino.h>
#include <ESPAsyncWebServer.h>

//------------------------------------------
//  WebSocket transport
//------------------------------------------
static AsyncWebSocketMessageHandler ws_handler;
static AsyncWebSocket ws("/ws/shell", ws_handler.eventHandler());
static AsyncWebSocketClient *active_client = nullptr;

static char ring_buf[config::ws_shell::RING_SIZE];
static char wbuf[config::ws_shell::WRITE_BUF];
static char line[config::shell::BUF_IN];

static void ws_flush(const char *data, size_t len, void *ctx) {
  (void)ctx;
  if (active_client)
    active_client->text(data, len);
}

static console::remote::Shell shell(
  ring_buf, config::ws_shell::RING_SIZE,
  wbuf, config::ws_shell::WRITE_BUF,
  line, config::shell::BUF_IN,
  ws_flush, nullptr
);

//------------------------------------------
//  WebSocket callbacks
//------------------------------------------
static void on_ws_connect(AsyncWebSocket *server, AsyncWebSocketClient *client) {
  (void)server;
  active_client = client;
  shell.reset();
  shell.send_motd("WebSocket");
  shell.send_prompt();
  Serial.printf("[ws_shell] client connected (id %u)\n", client->id());
}

static void on_ws_disconnect(AsyncWebSocket *server, uint32_t client_id) {
  (void)server;
  if (active_client && active_client->id() == client_id) {
    active_client = nullptr;
    Serial.println(F("[ws_shell] client disconnected"));
  }
}

static void on_ws_error(AsyncWebSocket *server, AsyncWebSocketClient *client,
                        uint16_t error_code, const char *reason, size_t len) {
  (void)server;
  (void)len;
  Serial.printf("[ws_shell] client %u error %u: %s\n", client->id(),
                error_code, reason ? reason : "");
}

static void on_ws_message(AsyncWebSocket *server, AsyncWebSocketClient *client,
                          const uint8_t *data, size_t len) {
  (void)server;
  if (!active_client || active_client->id() != client->id()) return;
  shell.push_input((const char *)data, len);
}

//------------------------------------------
//  Public API
//------------------------------------------
void services::ws_shell::registerRoutes(AsyncWebServer *server) {
  ws_handler.onConnect(on_ws_connect);
  ws_handler.onDisconnect(on_ws_disconnect);
  ws_handler.onError(on_ws_error);
  ws_handler.onMessage(on_ws_message);
  server->addHandler(&ws).addMiddleware([](AsyncWebServerRequest *request,
                                           ArMiddlewareNext next) {
    if (ws.count() > 0) {
      request->send(503, asyncsrv::T_text_plain, "Server is busy");
      return;
    }
    next();
  });
}

void services::ws_shell::service(void) {
  if (!active_client) return;
  shell.service();
  ws.cleanupClients(1);
}
