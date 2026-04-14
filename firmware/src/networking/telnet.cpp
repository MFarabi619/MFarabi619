#include "telnet.h"

#if CERATINA_TELNET_ENABLED

#include "../console/remote.h"
#include "../programs/led.h"

#include <Arduino.h>
#include <ESPTelnet.h>
#include <EscapeCodes.h>

//------------------------------------------
//  Telnet transport
//------------------------------------------
static ESPTelnet telnet_inst;
static EscapeCodes ansi;
static bool is_started = false;
static String client_ip_str;

static char ring_buf[config::telnet::RING_SIZE];
static char wbuf[config::telnet::WRITE_BUF];
static char line[config::shell::BUF_IN];

static void telnet_flush(const char *data, size_t len, void *ctx) {
  (void)ctx;
  telnet_inst.write((const uint8_t *)data, len);
}

static console::remote::Shell shell(
  ring_buf, config::telnet::RING_SIZE,
  wbuf, config::telnet::WRITE_BUF,
  line, config::shell::BUF_IN,
  telnet_flush, nullptr
);

//------------------------------------------
//  Connection callbacks
//------------------------------------------
static void on_connect(String ip) {
  client_ip_str = ip;
  Serial.printf("[telnet] client connected from %s\n", ip.c_str());
  LED.set(colors::Cyan);
  shell.reset();
  telnet_inst.print(ansi.cls());
  shell.send_motd("Telnet");
  shell.send_prompt();
}

static void on_disconnect(String ip) {
  Serial.printf("[telnet] client disconnected (%s)\n", ip.c_str());
  client_ip_str = "";
  LED.set(colors::Green);
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
    shell.push_input(ch);
  }
}

void networking::telnet::initialize() {
  if (is_started) return;

//------------------------------------------
//  Public API
//------------------------------------------
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

  is_started = true;
  Serial.printf("[telnet] listening on port %d\n", config::telnet::PORT);
}

void networking::telnet::service() {
  if (!is_started) return;
  telnet_inst.loop();
  if (!telnet_inst.isConnected()) return;
  shell.service();
}

bool networking::telnet::isConnected() {
  return is_started && telnet_inst.isConnected();
}

const char *networking::telnet::clientIP() {
  return client_ip_str.c_str();
}

void networking::telnet::disconnect() {
  if (is_started && telnet_inst.isConnected())
    telnet_inst.disconnectClient();
}

#else

void networking::telnet::initialize() {}
void networking::telnet::service() {}
bool networking::telnet::isConnected() { return false; }
const char *networking::telnet::clientIP() { return ""; }
void networking::telnet::disconnect() {}

#endif

#ifdef PIO_UNIT_TESTING

#include "telnet.h"
#include "../testing/it.h"

#include <Arduino.h>

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
