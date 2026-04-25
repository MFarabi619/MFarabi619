#include "tunnel.h"

#if CERATINA_TUNNEL_ENABLED

#include <Arduino.h>
#include <WiFi.h>
#include <lwip/sockets.h>

// ─────────────────────────────────────────────────────────────────────────────
//  bore.pub TCP tunnel client
//
//  Protocol (bore v0.5+):
//    Control port 7835, JSON messages delimited by \0
//    Client sends {"Hello":0}\0       → server replies {"Hello":PORT}\0
//    Server sends {"Connection":"UUID"}\0  → client opens new TCP to 7835,
//      sends {"Accept":"UUID"}\0, then proxies raw TCP ↔ local port.
// ─────────────────────────────────────────────────────────────────────────────

namespace {

constexpr uint16_t CONTROL_PORT   = 7835;
constexpr uint16_t LOCAL_PORT     = 80;
constexpr int      MAX_PROXY      = 4;
constexpr int      CONNECT_MS     = 10000;
constexpr int      LOCAL_TIMEOUT  = 5000;
constexpr uint32_t PROXY_IDLE_MS  = 30000;

enum Phase { IDLE, INIT, SERVE, WAIT };

struct BoreState {
  String host;
  String url;
  uint16_t remote_port;
  Phase phase;
  unsigned long wait_until;
  unsigned long backoff;
  bool is_ready;
  bool is_stopped;
  bool is_started;
};

static BoreState bore = {};
static WiFiClient control_connection;
static WiFiClient proxy_connections[MAX_PROXY];
static WiFiClient local_connections[MAX_PROXY];

// ─────────────────────────────────────────────────────────────────────────────
//  TCP helpers
// ─────────────────────────────────────────────────────────────────────────────

void configure_keepalive(WiFiClient &client) {
  int file_descriptor = client.fd();
  if (file_descriptor < 0) return;
  int enabled = 1, idle = 10, interval = 10, count = 3;
  setsockopt(file_descriptor, SOL_SOCKET,  SO_KEEPALIVE,  &enabled,  sizeof(enabled));
  setsockopt(file_descriptor, IPPROTO_TCP, TCP_KEEPIDLE,  &idle,     sizeof(idle));
  setsockopt(file_descriptor, IPPROTO_TCP, TCP_KEEPINTVL, &interval, sizeof(interval));
  setsockopt(file_descriptor, IPPROTO_TCP, TCP_KEEPCNT,   &count,    sizeof(count));
  setsockopt(file_descriptor, IPPROTO_TCP, TCP_NODELAY,   &enabled,  sizeof(enabled));
  client.setNoDelay(true);
}

bool connect_to_host(WiFiClient &client, const char *host, uint16_t port) {
  return client.connect(host, port, CONNECT_MS);
}

bool connect_to_local(WiFiClient &client) {
  return client.connect(IPAddress(127, 0, 0, 1), LOCAL_PORT, LOCAL_TIMEOUT);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Null-delimited JSON framing
// ─────────────────────────────────────────────────────────────────────────────

String receive_message(WiFiClient &client, int timeout_ms = 5000) {
  String message;
  message.reserve(128);
  unsigned long started_at = millis();
  while (millis() - started_at < (unsigned long)timeout_ms) {
    if (!client.connected()) return "";
    if (!client.available()) { vTaskDelay(pdMS_TO_TICKS(1)); continue; }
    char character = client.read();
    if (character == '\0') return message;
    message += character;
    if (message.length() > 256) return "";
  }
  return "";
}

void send_message(WiFiClient &client, const String &message) {
  client.print(message);
  client.write((uint8_t)0);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Message parsing
// ─────────────────────────────────────────────────────────────────────────────

int parse_hello_port(const String &message) {
  int position = message.indexOf("\"Hello\"");
  if (position < 0) return -1;
  position += 7;
  while (position < (int)message.length() && (message[position] == ':' || message[position] == ' ')) position++;
  return atoi(message.c_str() + position);
}

String parse_connection_uuid(const String &message) {
  int position = message.indexOf("\"Connection\"");
  if (position < 0) return "";
  position += 12;
  while (position < (int)message.length() && (message[position] == ':' || message[position] == ' ')) position++;
  if (position >= (int)message.length() || message[position] != '"') return "";
  position++;
  int start = position;
  while (position < (int)message.length() && message[position] != '"') position++;
  return message.substring(start, position);
}

String parse_error(const String &message) {
  int position = message.indexOf("\"Error\"");
  if (position < 0) return "";
  position += 7;
  while (position < (int)message.length() && (message[position] == ':' || message[position] == ' ')) position++;
  if (position >= (int)message.length() || message[position] != '"') return "";
  position++;
  int start = position;
  while (position < (int)message.length() && message[position] != '"') position++;
  return message.substring(start, position);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bidirectional TCP proxy
// ─────────────────────────────────────────────────────────────────────────────

void proxy_bytes(WiFiClient &remote, WiFiClient &local) {
  uint8_t buffer[512];
  unsigned long last_activity = millis();
  while (remote.connected() && local.connected() && millis() - last_activity < PROXY_IDLE_MS) {
    bool has_activity = false;
    if (remote.available()) {
      int bytes_read = remote.read(buffer, sizeof(buffer));
      if (bytes_read > 0) { local.write(buffer, bytes_read); has_activity = true; }
    }
    if (local.available()) {
      int bytes_read = local.read(buffer, sizeof(buffer));
      if (bytes_read > 0) { remote.write(buffer, bytes_read); has_activity = true; }
    }
    if (has_activity) last_activity = millis();
    else vTaskDelay(pdMS_TO_TICKS(1));
  }
  remote.stop();
  local.stop();
}

void accept_connection(const String &uuid, int slot) {
  WiFiClient &proxy = proxy_connections[slot];
  WiFiClient &local = local_connections[slot];

  if (!connect_to_host(proxy, bore.host.c_str(), CONTROL_PORT)) return;
  send_message(proxy, "{\"Accept\":\"" + uuid + "\"}");

  if (!connect_to_local(local)) { proxy.stop(); return; }
  local.setNoDelay(true);
  proxy_bytes(proxy, local);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Control connection lifecycle
// ─────────────────────────────────────────────────────────────────────────────

bool establish_tunnel() {
  if (WiFi.status() != WL_CONNECTED) return false;
  if (control_connection.connected()) control_connection.stop();

  if (!connect_to_host(control_connection, bore.host.c_str(), CONTROL_PORT)) return false;
  configure_keepalive(control_connection);

  send_message(control_connection, "{\"Hello\":0}");

  String response = receive_message(control_connection, 10000);
  if (!response.length()) { control_connection.stop(); return false; }

  String error = parse_error(response);
  if (error.length()) {
    Serial.printf("[tunnel] bore error: %s\n", error.c_str());
    control_connection.stop();
    return false;
  }

  int port = parse_hello_port(response);
  if (port <= 0) { control_connection.stop(); return false; }

  bore.remote_port = (uint16_t)port;
  bore.url = "http://" + bore.host + ":" + String(port);
  bore.is_ready = true;
  Serial.printf("[tunnel] public URL: %s\n", bore.url.c_str());
  return true;
}

bool serve_connections() {
  if (!control_connection.connected()) return false;
  if (!control_connection.available()) return true;

  String message = receive_message(control_connection, 3000);
  if (!message.length()) return control_connection.connected();

  if (message.indexOf("\"Heartbeat\"") >= 0) return true;

  String uuid = parse_connection_uuid(message);
  if (!uuid.length()) return true;

  int slot = -1;
  for (int index = 0; index < MAX_PROXY; index++) {
    if (!proxy_connections[index].connected() && !local_connections[index].connected()) {
      slot = index;
      break;
    }
  }
  if (slot < 0) return true;

  accept_connection(uuid, slot);
  return true;
}

void run_state_machine() {
  if (!bore.is_started || bore.is_stopped) return;
  switch (bore.phase) {
    case IDLE:
      break;
    case INIT:
      if (establish_tunnel()) {
        bore.phase = SERVE;
        bore.backoff = 2000;
      } else {
        bore.phase = WAIT;
        bore.wait_until = millis() + bore.backoff;
        bore.backoff = min(bore.backoff * 2, 60000UL);
      }
      break;
    case SERVE:
      if (!serve_connections()) {
        control_connection.stop();
        bore.is_ready = false;
        bore.phase = WAIT;
        bore.wait_until = millis() + bore.backoff;
        bore.backoff = min(bore.backoff * 2, 60000UL);
      }
      break;
    case WAIT:
      if (millis() >= bore.wait_until) bore.phase = INIT;
      break;
  }
}

}

// ─────────────────────────────────────────────────────────────────────────────
//  Public API
// ─────────────────────────────────────────────────────────────────────────────

void networking::tunnel::initialize() {
  if (bore.is_started) return;
  bore.host = "bore.pub";
  bore.is_stopped = false;
  bore.is_ready = false;
  bore.is_started = true;
  bore.backoff = 2000;
  bore.url = "(connecting...)";
  bore.phase = INIT;
  Serial.println(F("[tunnel] bore tunnel starting"));
}

void networking::tunnel::service() {
  if (!bore.is_started) return;
  run_state_machine();
}

bool networking::tunnel::isReady() {
  return bore.is_started && bore.is_ready;
}

const char *networking::tunnel::accessURL() {
  return bore.url.c_str();
}

#else

void networking::tunnel::initialize() {}
void networking::tunnel::service() {}
bool networking::tunnel::isReady() { return false; }
const char *networking::tunnel::accessURL() { return ""; }

#endif

// ─────────────────────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING

#include "tunnel.h"
#include <testing/utils.h>

namespace networking::tunnel { void test(void); }

static void test_tunnel_config(void) {
  GIVEN("tunnel feature flag");
  THEN("the configuration is valid");

#if CERATINA_TUNNEL_ENABLED
  TEST_MESSAGE("tunnel enabled (CERATINA_TUNNEL_ENABLED=1)");
#else
  TEST_MESSAGE("tunnel disabled (CERATINA_TUNNEL_ENABLED=0)");
#endif
}

static void test_tunnel_noop_when_disabled(void) {
  WHEN("tunnel functions are called while disabled");
  THEN("they complete as no-ops");
#if !CERATINA_TUNNEL_ENABLED
  networking::tunnel::initialize();
  networking::tunnel::service();
  TEST_ASSERT_FALSE_MESSAGE(networking::tunnel::isReady(),
    "device: tunnel should not be ready when disabled");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("", networking::tunnel::accessURL(),
    "device: tunnel URL should be empty when disabled");
#else
  TEST_IGNORE_MESSAGE("tunnel is enabled — test not applicable");
#endif
}

void networking::tunnel::test(void) {
  MODULE("Tunnel");
  RUN_TEST(test_tunnel_config);
  RUN_TEST(test_tunnel_noop_when_disabled);
}

#endif
