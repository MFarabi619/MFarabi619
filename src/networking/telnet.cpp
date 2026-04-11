#include "telnet.h"

#if CONFIG_TELNET_ENABLED

#include "../programs/shell/shell.h"
#include "../programs/shell/microfetch.h"

#include <Arduino.h>
#include <ESPTelnet.h>
#include <EscapeCodes.h>
#include <microshell.h>

static ESPTelnet telnet;
static EscapeCodes ansi;
static bool started = false;
static String client_ip;

static volatile uint16_t ring_head = 0;
static volatile uint16_t ring_tail = 0;
static char ring_buf[CONFIG_TELNET_RING_SIZE];

static char write_buf[CONFIG_TELNET_WRITE_BUF];
static size_t write_buf_pos = 0;

static struct ush_object telnet_ush;
static char telnet_in_buf[CONFIG_SHELL_BUF_IN];
static char telnet_out_buf[CONFIG_SHELL_BUF_OUT];

static void ring_reset(void) { ring_head = 0; ring_tail = 0; }

static bool ring_push(char ch) {
  uint16_t next = (ring_head + 1) % CONFIG_TELNET_RING_SIZE;
  if (next == ring_tail) return false;
  ring_buf[ring_head] = ch;
  ring_head = next;
  return true;
}

static int ring_pop(char *ch) {
  if (ring_head == ring_tail) return 0;
  *ch = ring_buf[ring_tail];
  ring_tail = (ring_tail + 1) % CONFIG_TELNET_RING_SIZE;
  return 1;
}

static void write_flush(void) {
  if (write_buf_pos == 0) return;
  telnet.write((const uint8_t *)write_buf, write_buf_pos);
  write_buf_pos = 0;
}

static int telnet_shell_read(struct ush_object *self, char *ch) {
  (void)self;
  return ring_pop(ch);
}

static int telnet_shell_write(struct ush_object *self, char ch) {
  (void)self;
  if (!telnet.isConnected()) return 0;
  write_buf[write_buf_pos++] = ch;
  if (write_buf_pos >= CONFIG_TELNET_WRITE_BUF)
    write_flush();
  return 1;
}

static const struct ush_io_interface telnet_shell_io = {
  .read = telnet_shell_read,
  .write = telnet_shell_write,
};

static const struct ush_descriptor telnet_shell_desc = {
  .io = &telnet_shell_io,
  .input_buffer = telnet_in_buf,
  .input_buffer_size = sizeof(telnet_in_buf),
  .output_buffer = telnet_out_buf,
  .output_buffer_size = sizeof(telnet_out_buf),
  .path_max_length = CONFIG_SHELL_PATH_MAX,
  .hostname = shell_get_hostname(),
};

static void on_connect(String ip) {
  client_ip = ip;
  Serial.printf("[telnet] client connected from %s\n", ip.c_str());
  ring_reset();
  write_buf_pos = 0;
  shell_init_instance(&telnet_ush, &telnet_shell_desc);

  telnet.print(ansi.cls());
  const char *motd = microfetch_generate();
  telnet.write((const uint8_t *)motd, strlen(motd));
}

static void on_disconnect(String ip) {
  Serial.printf("[telnet] client disconnected (%s)\n", ip.c_str());
  client_ip = "";
}

static void on_reconnect(String ip) {
  Serial.printf("[telnet] client reconnected from %s\n", ip.c_str());
}

static void on_connection_attempt(String ip) {
  Serial.printf("[telnet] rejected connection from %s (session active: %s)\n",
                ip.c_str(), client_ip.c_str());
}

static void on_input(String input) {
  for (size_t i = 0; i < input.length(); i++) {
    char ch = input[i];
    if (ch == '\r') continue;
    ring_push(ch);
  }
}

void telnet_start(void) {
  if (started) return;

  telnet.onConnect(on_connect);
  telnet.onDisconnect(on_disconnect);
  telnet.onReconnect(on_reconnect);
  telnet.onConnectionAttempt(on_connection_attempt);
  telnet.onInputReceived(on_input);
  telnet.setLineMode(false);
  telnet.setKeepAliveInterval(CONFIG_TELNET_KEEPALIVE_MS);

  if (!telnet.begin(CONFIG_TELNET_PORT, false)) {
    Serial.println(F("[telnet] failed to start"));
    return;
  }

  started = true;
  Serial.printf("[telnet] listening on port %d\n", CONFIG_TELNET_PORT);
}

void telnet_service(void) {
  if (!started) return;
  telnet.loop();
  if (!telnet.isConnected()) return;
  while (ush_service(&telnet_ush)) {}
  write_flush();
}

bool telnet_is_connected(void) {
  return started && telnet.isConnected();
}

const char *telnet_client_ip(void) {
  return client_ip.c_str();
}

void telnet_disconnect(void) {
  if (started && telnet.isConnected())
    telnet.disconnectClient();
}

#else

void telnet_start(void) {}
void telnet_service(void) {}
bool telnet_is_connected(void) { return false; }
const char *telnet_client_ip(void) { return ""; }
void telnet_disconnect(void) {}

#endif
