#include "ws_shell.h"
#include "../config.h"
#include "../programs/shell/shell.h"
#include "../programs/shell/session.h"
#include "../services/identity.h"
#include "../programs/shell/microfetch.h"

#include <Arduino.h>
#include <ESPAsyncWebServer.h>
#include <microshell.h>

static AsyncWebSocketMessageHandler ws_handler;
static AsyncWebSocket ws("/ws/shell", ws_handler.eventHandler());
static AsyncWebSocketClient *active_client = nullptr;

static char ring_buf[config::ws_shell::RING_SIZE];
static char write_buf[config::ws_shell::WRITE_BUF];
static programs::shell::session::RingBuffer ring = {
  .data = ring_buf,
  .capacity = config::ws_shell::RING_SIZE,
  .head = 0,
  .tail = 0,
};
static programs::shell::session::WriteBuffer write_state = {
  .data = write_buf,
  .capacity = config::ws_shell::WRITE_BUF,
  .position = 0,
};

static void write_flush(void) {
  if (write_state.position == 0 || !active_client) return;
  active_client->text(write_buf, write_state.position);
  programs::shell::session::reset(&write_state);
}

static int ws_shell_read(struct ush_object *self, char *ch) {
  (void)self;
  return programs::shell::session::pop(&ring, ch);
}

static int ws_shell_write(struct ush_object *self, char ch) {
  (void)self;
  if (!active_client) return 0;
  if (!programs::shell::session::push(&write_state, ch)) return 0;
  if (write_state.position >= config::ws_shell::WRITE_BUF)
    write_flush();
  return 1;
}

static const struct ush_io_interface ws_shell_io = {
  .read = ws_shell_read,
  .write = ws_shell_write,
};

static char ws_in_buf[config::shell::BUF_IN];
static char ws_out_buf[config::shell::BUF_OUT];
static struct ush_object ws_ush;

static const struct ush_descriptor ws_shell_desc = {
  .io = &ws_shell_io,
  .input_buffer = ws_in_buf,
  .input_buffer_size = sizeof(ws_in_buf),
  .output_buffer = ws_out_buf,
  .output_buffer_size = sizeof(ws_out_buf),
  .path_max_length = config::shell::MAX_PATH_LEN,
  .hostname = const_cast<char *>(services::identity::accessHostname()),
};

static void on_ws_connect(AsyncWebSocket *server, AsyncWebSocketClient *client) {
  (void)server;
  active_client = client;
  programs::shell::session::reset(&ring);
  programs::shell::session::reset(&write_state);
  programs::shell::initInstance(&ws_ush, &ws_shell_desc);
  const char *motd = programs::shell::microfetch::generate();
  client->text(motd, strlen(motd));
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

  for (size_t i = 0; i < len; i++) {
    programs::shell::session::push(&ring, (char)data[i]);
  }
}

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
  while (ush_service(&ws_ush)) {}
  write_flush();
  ws.cleanupClients(1);
}
