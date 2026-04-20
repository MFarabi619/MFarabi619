#include "ws_shell.h"
#include <config.h>
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
    shell.save_history();
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

//------------------------------------------
//  Tests
//------------------------------------------
#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

// TODO: WebSocket shell tests require a connected AsyncWebSocketClient,
// which needs the HTTP server running and a WebSocket client on the network.
// Test via the e2e test suite or browser dev tools.
//
// static void ws_shell_test_service_without_client(void) {
//   TEST_MESSAGE("user calls ws_shell service with no connected client");
//   services::ws_shell::service();
//   TEST_MESSAGE("service returned without error");
// }
//
// static void ws_shell_test_command_dispatch(void) {
//   TEST_MESSAGE("user sends a command via WebSocket and receives output");
//   // Requires: WebSocket client connected to ws://device/ws/shell
//   // Send "help\n", verify response contains command list
// }
//
// static void ws_shell_test_prompt_rendered(void) {
//   TEST_MESSAGE("user connects via WebSocket and receives powerline prompt");
//   // Requires: WebSocket client connected
//   // Verify MOTD + prompt sent on connect
// }
//
// static void ws_shell_test_max_one_client(void) {
//   TEST_MESSAGE("user verifies second WebSocket client gets 503");
//   // Requires: two WebSocket clients
//   // First connects OK, second gets 503 from middleware
// }

void services::ws_shell::test() {
  // TODO: Uncomment when WebSocket test client is available
  // it("user calls ws_shell service without client", ws_shell_test_service_without_client);
  // it("user sends command via WebSocket", ws_shell_test_command_dispatch);
  // it("user receives prompt on WebSocket connect", ws_shell_test_prompt_rendered);
  // it("user verifies max one WebSocket client", ws_shell_test_max_one_client);
}

#endif
