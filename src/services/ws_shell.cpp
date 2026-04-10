#include "ws_shell.h"
#include "../config.h"
#include "../programs/shell/shell.h"
#include "../programs/shell/microfetch.h"

#include <Arduino.h>
#include <microshell.h>

static AsyncWebSocket ws("/ws/shell");
static AsyncWebSocketClient *active_client = nullptr;

static volatile uint16_t ring_head = 0;
static volatile uint16_t ring_tail = 0;
static char ring_buf[CONFIG_WS_SHELL_RING_SIZE];

static char write_buf[CONFIG_WS_SHELL_WRITE_BUF];
static size_t write_buf_pos = 0;

static void ring_reset(void) { ring_head = 0; ring_tail = 0; }

static bool ring_push(char ch) {
  uint16_t next = (ring_head + 1) % CONFIG_WS_SHELL_RING_SIZE;
  if (next == ring_tail) return false;
  ring_buf[ring_head] = ch;
  ring_head = next;
  return true;
}

static int ring_pop(char *ch) {
  if (ring_head == ring_tail) return 0;
  *ch = ring_buf[ring_tail];
  ring_tail = (ring_tail + 1) % CONFIG_WS_SHELL_RING_SIZE;
  return 1;
}

static void write_flush(void) {
  if (write_buf_pos == 0 || !active_client) return;
  active_client->text(write_buf, write_buf_pos);
  write_buf_pos = 0;
}

static int ws_shell_read(struct ush_object *self, char *ch) {
  (void)self;
  return ring_pop(ch);
}

static int ws_shell_write(struct ush_object *self, char ch) {
  (void)self;
  if (!active_client) return 0;
  write_buf[write_buf_pos++] = ch;
  if (write_buf_pos >= CONFIG_WS_SHELL_WRITE_BUF)
    write_flush();
  return 1;
}

static const struct ush_io_interface ws_shell_io = {
  .read = ws_shell_read,
  .write = ws_shell_write,
};

static char ws_in_buf[CONFIG_SHELL_BUF_IN];
static char ws_out_buf[CONFIG_SHELL_BUF_OUT];
static struct ush_object ws_ush;

static const struct ush_descriptor ws_shell_desc = {
  .io = &ws_shell_io,
  .input_buffer = ws_in_buf,
  .input_buffer_size = sizeof(ws_in_buf),
  .output_buffer = ws_out_buf,
  .output_buffer_size = sizeof(ws_out_buf),
  .path_max_length = CONFIG_SHELL_PATH_MAX,
  .hostname = shell_get_hostname(),
};

static void on_ws_event(AsyncWebSocket *server, AsyncWebSocketClient *client,
                        AwsEventType type, void *arg, uint8_t *data, size_t len) {
  (void)server;

  if (type == WS_EVT_CONNECT) {
    if (active_client) {
      client->text("[busy: another session is active]\r\n");
      client->close();
      return;
    }
    active_client = client;
    ring_reset();
    write_buf_pos = 0;
    shell_init_instance(&ws_ush, &ws_shell_desc);
    const char *motd = microfetch_generate();
    client->text(motd, strlen(motd));
    Serial.printf("[ws_shell] client connected (id %u)\n", client->id());

  } else if (type == WS_EVT_DISCONNECT) {
    if (active_client && active_client->id() == client->id()) {
      active_client = nullptr;
      Serial.println(F("[ws_shell] client disconnected"));
    }

  } else if (type == WS_EVT_DATA) {
    AwsFrameInfo *info = (AwsFrameInfo *)arg;
    if (info->message_opcode == WS_TEXT && info->final && info->index == 0 && info->len == len) {
      for (size_t i = 0; i < len; i++) {
        ring_push((char)data[i]);
      }
    }
  }
}

void ws_shell_register(AsyncWebServer *server) {
  ws.onEvent(on_ws_event);
  server->addHandler(&ws);
}

void ws_shell_service(void) {
  if (!active_client) return;
  while (ush_service(&ws_ush)) {}
  write_flush();
  ws.cleanupClients(1);
}
