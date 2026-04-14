#include "telnet.h"

#if CERATINA_TELNET_ENABLED

#include "../programs/shell/shell.h"
#include "../programs/shell/session.h"
#include "../services/identity.h"
#include "../programs/shell/microfetch.h"
#include "../programs/led.h"

#include <Arduino.h>
#include <ESPTelnet.h>
#include <EscapeCodes.h>
#include <microshell.h>

static ESPTelnet telnet_inst;
static EscapeCodes ansi;
static bool started = false;
static String client_ip_str;

static char ring_buf[config::telnet::RING_SIZE];
static char write_buf[config::telnet::WRITE_BUF];
static programs::shell::session::RingBuffer ring = {
  .data = ring_buf,
  .capacity = config::telnet::RING_SIZE,
  .head = 0,
  .tail = 0,
};
static programs::shell::session::WriteBuffer write_state = {
  .data = write_buf,
  .capacity = config::telnet::WRITE_BUF,
  .position = 0,
};

static struct ush_object telnet_ush;
static char telnet_in_buf[config::shell::BUF_IN];
static char telnet_out_buf[config::shell::BUF_OUT];

static void write_flush(void) {
  if (write_state.position == 0) return;
  telnet_inst.write((const uint8_t *)write_buf, write_state.position);
  programs::shell::session::reset(&write_state);
}

static int telnet_shell_read(struct ush_object *self, char *ch) {
  (void)self;
  return programs::shell::session::pop(&ring, ch);
}

static int telnet_shell_write(struct ush_object *self, char ch) {
  (void)self;
  if (!telnet_inst.isConnected()) return 0;
  if (!programs::shell::session::push(&write_state, ch)) return 0;
  if (write_state.position >= config::telnet::WRITE_BUF)
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
  .hostname = const_cast<char *>(services::identity::accessHostname()),
};

static void on_connect(String ip) {
  client_ip_str = ip;
  Serial.printf("[telnet] client connected from %s\n", ip.c_str());
  LED.set(CRGB::Cyan);
  programs::shell::session::reset(&ring);
  programs::shell::session::reset(&write_state);
  programs::shell::initInstance(&telnet_ush, &telnet_shell_desc);

  telnet_inst.print(ansi.cls());
  const char *motd = programs::shell::microfetch::generate();
  telnet_inst.write((const uint8_t *)motd, strlen(motd));
}

static void on_disconnect(String ip) {
  Serial.printf("[telnet] client disconnected (%s)\n", ip.c_str());
  client_ip_str = "";
  LED.set(CRGB::Green);
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
    programs::shell::session::push(&ring, ch);
  }
}

void networking::telnet::initialize() {
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

void networking::telnet::service() {
  if (!started) return;
  telnet_inst.loop();
  if (!telnet_inst.isConnected()) return;
  while (ush_service(&telnet_ush)) {}
  write_flush();
}

bool networking::telnet::isConnected() {
  return started && telnet_inst.isConnected();
}

const char *networking::telnet::clientIP() {
  return client_ip_str.c_str();
}

void networking::telnet::disconnect() {
  if (started && telnet_inst.isConnected())
    telnet_inst.disconnectClient();
}

#else

void networking::telnet::initialize() {}
void networking::telnet::service() {}
bool networking::telnet::isConnected() { return false; }
const char *networking::telnet::clientIP() { return ""; }
void networking::telnet::disconnect() {}

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
