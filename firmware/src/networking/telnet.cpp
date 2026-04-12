#include "telnet.h"

#if CERATINA_TELNET_ENABLED

#include "../programs/shell/shell.h"
#include "../programs/shell/microfetch.h"
#include "../programs/led.h"
#include <ColorFormat.h>

#include <Arduino.h>
#include <ESPTelnet.h>
#include <EscapeCodes.h>
#include <microshell.h>

static ESPTelnet telnet_inst;
static EscapeCodes ansi;
static bool started = false;
static String client_ip_str;

static volatile uint16_t ring_head = 0;
static volatile uint16_t ring_tail = 0;
static char ring_buf[config::telnet::RING_SIZE];

static char write_buf[config::telnet::WRITE_BUF];
static size_t write_buf_pos = 0;

static struct ush_object telnet_ush;
static char telnet_in_buf[config::shell::BUF_IN];
static char telnet_out_buf[config::shell::BUF_OUT];

static void ring_reset(void) { ring_head = 0; ring_tail = 0; }

static bool ring_push(char ch) {
  uint16_t next = (ring_head + 1) % config::telnet::RING_SIZE;
  if (next == ring_tail) return false;
  ring_buf[ring_head] = ch;
  ring_head = next;
  return true;
}

static int ring_pop(char *ch) {
  if (ring_head == ring_tail) return 0;
  *ch = ring_buf[ring_tail];
  ring_tail = (ring_tail + 1) % config::telnet::RING_SIZE;
  return 1;
}

static void write_flush(void) {
  if (write_buf_pos == 0) return;
  telnet_inst.write((const uint8_t *)write_buf, write_buf_pos);
  write_buf_pos = 0;
}

static int telnet_shell_read(struct ush_object *self, char *ch) {
  (void)self;
  return ring_pop(ch);
}

static int telnet_shell_write(struct ush_object *self, char ch) {
  (void)self;
  if (!telnet_inst.isConnected()) return 0;
  write_buf[write_buf_pos++] = ch;
  if (write_buf_pos >= config::telnet::WRITE_BUF)
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
  .path_max_length = config::shell::MAX_PATH_LEN,
  .hostname = programs::shell::accessHostname(),
};

static void on_connect(String ip) {
  client_ip_str = ip;
  Serial.printf("[telnet] client connected from %s\n", ip.c_str());
  LED.set(RGB_CYAN);
  ring_reset();
  write_buf_pos = 0;
  programs::shell::initInstance(&telnet_ush, &telnet_shell_desc);

  telnet_inst.print(ansi.cls());
  const char *motd = programs::shell::microfetch::generate();
  telnet_inst.write((const uint8_t *)motd, strlen(motd));
}

static void on_disconnect(String ip) {
  Serial.printf("[telnet] client disconnected (%s)\n", ip.c_str());
  client_ip_str = "";
  LED.set(RGB_GREEN);
}

static void on_reconnect(String ip) {
  Serial.printf("[telnet] client reconnected from %s\n", ip.c_str());
}

static void on_connection_attempt(String ip) {
  Serial.printf("[telnet] rejected connection from %s (session active: %s)\n",
                ip.c_str(), client_ip_str.c_str());
}

static void on_input(String input) {
  for (size_t i = 0; i < input.length(); i++) {
    char ch = input[i];
    if (ch == '\r') continue;
    ring_push(ch);
  }
}

void networking::telnet::initialize() noexcept {
  if (started) return;

  telnet_inst.onConnect(on_connect);
  telnet_inst.onDisconnect(on_disconnect);
  telnet_inst.onReconnect(on_reconnect);
  telnet_inst.onConnectionAttempt(on_connection_attempt);
  telnet_inst.onInputReceived(on_input);
  telnet_inst.setLineMode(false);
  telnet_inst.setKeepAliveInterval(config::telnet::KEEPALIVE_MS);

  if (!telnet_inst.begin(config::telnet::PORT, false)) {
    Serial.println(F("[telnet] failed to start"));
    return;
  }

  started = true;
  Serial.printf("[telnet] listening on port %d\n", config::telnet::PORT);
}

void networking::telnet::service() noexcept {
  if (!started) return;
  telnet_inst.loop();
  if (!telnet_inst.isConnected()) return;
  while (ush_service(&telnet_ush)) {}
  write_flush();
}

bool networking::telnet::isConnected() noexcept {
  return started && telnet_inst.isConnected();
}

const char *networking::telnet::clientIP() noexcept {
  return client_ip_str.c_str();
}

void networking::telnet::disconnect() noexcept {
  if (started && telnet_inst.isConnected())
    telnet_inst.disconnectClient();
}

#else

void networking::telnet::initialize() noexcept {}
void networking::telnet::service() noexcept {}
bool networking::telnet::isConnected() noexcept { return false; }
const char *networking::telnet::clientIP() noexcept { return ""; }
void networking::telnet::disconnect() noexcept {}

#endif

// ─────────────────────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING


#include "telnet.h"
#include "wifi.h"
#include "../testing/it.h"

namespace networking::telnet { void test(void); }

#include <Arduino.h>
#include <WiFi.h>

static void telnet_test_config(void) {
  TEST_MESSAGE("user verifies telnet configuration");

#if CERATINA_TELNET_ENABLED
  TEST_ASSERT_GREATER_THAN_UINT16_MESSAGE(0, config::telnet::PORT,
    "device: telnet port must be > 0");
  TEST_ASSERT_GREATER_THAN_UINT16_MESSAGE(0, config::telnet::RING_SIZE,
    "device: ring buffer must be > 0");
  TEST_ASSERT_GREATER_THAN_UINT16_MESSAGE(0, config::telnet::WRITE_BUF,
    "device: write buffer must be > 0");

  char msg[64];
  snprintf(msg, sizeof(msg), "telnet enabled on port %d", config::telnet::PORT);
  TEST_MESSAGE(msg);
#else
  TEST_IGNORE_MESSAGE("telnet not enabled");

#endif
}

void networking::telnet::test(void) {
  it("user verifies telnet configuration",
     telnet_test_config);
}

#endif
