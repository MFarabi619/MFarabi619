#include "tunnel.h"

#include <string.h>

#if CERATINA_TUNNEL_ENABLED

#include "../services/preferences.h"
#include <identity.h>

#include <Arduino.h>
#include <Preferences.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <lwip/sockets.h>

#include <time.h>

namespace {

constexpr uint16_t kBoreControlPort = 7835;
constexpr int kMaximumProxyConnections = 4;
constexpr int kMaximumHeaderSize = 4096;
constexpr int kMaximumBodySize = 16384;
constexpr int kDrainTimeoutMilliseconds = 200;
constexpr int kHeaderTimeoutMilliseconds = 3000;
constexpr unsigned long kReconnectBackoffInitialMilliseconds = 2000;
constexpr unsigned long kReconnectBackoffMaximumMilliseconds = 60000;
constexpr unsigned long kSelfHostedPingIntervalMilliseconds = 25000;

struct SelfHostedState {
  WiFiClient plain_websocket;
  WiFiClient local_http;
  WiFiClientSecure *secure_websocket = nullptr;
  WiFiClient *websocket = nullptr;
  String origin;
  String relay_host;
  String device_path;
  uint16_t relay_port = 0;
  bool use_tls = false;
  unsigned long last_ping_at = 0;
};

struct State {
  networking::tunnel::Config config = {};
  networking::tunnel::Snapshot snapshot = {};
  bool config_loaded = false;
  networking::tunnel::Phase phase = networking::tunnel::PhaseIdle;
  unsigned long wait_until = 0;
  unsigned long backoff = 0;
  SelfHostedState self_hosted = {};
};

static State state = {};

static WiFiClient bore_control_connection;
static WiFiClient bore_proxy_connections[kMaximumProxyConnections];
static WiFiClient bore_local_connections[kMaximumProxyConnections];

const char *provider_name(networking::tunnel::Provider provider) {
  switch (provider) {
    case networking::tunnel::ProviderBore:
      return "bore";
    case networking::tunnel::ProviderSelfHosted:
      return "self-hosted";
    case networking::tunnel::ProviderLocaltunnel:
      return "localtunnel";
    default:
      return "disabled";
  }
}

String normalize_device_path_identifier(const String &raw_identifier);

void delay_short() {
  vTaskDelay(pdMS_TO_TICKS(1));
}

void clear_snapshot_runtime_fields() {
  state.snapshot.started = false;
  state.snapshot.stopped = false;
  state.snapshot.ready = false;
  state.snapshot.phase = networking::tunnel::PhaseIdle;
  state.snapshot.remote_port = 0;
  state.snapshot.url[0] = '\0';
  state.snapshot.last_client_ip[0] = '\0';
  state.snapshot.connect_attempts = 0;
  state.snapshot.backoff_ms = 0;
  state.snapshot.last_error_at = 0;
  state.snapshot.last_error[0] = '\0';
}

void record_error(const char *message) {
  state.snapshot.last_error_at = millis();
  strlcpy(state.snapshot.last_error, message ? message : "unknown", sizeof(state.snapshot.last_error));
}

String trim_and_strip_trailing_slashes(const char *value) {
  String normalized = value ? value : "";
  normalized.trim();
  while (normalized.endsWith("/")) {
    normalized.remove(normalized.length() - 1);
  }
  return normalized;
}

String derive_default_device_path() {
  char device_name[64] = {};
  IdentityStringQuery device_name_query = {
    .buffer = device_name,
    .capacity = sizeof(device_name),
    .ok = false,
  };

  const char *source = services::identity::access_hostname();
  if (services::identity::access_device_name(&device_name_query) && device_name[0] != '\0') {
    source = device_name;
  }

  String path = source ? source : config::HOSTNAME;
  path.trim();
  path.toLowerCase();

  String sanitized = normalize_device_path_identifier(path);

  if (!sanitized.length()) {
    sanitized = config::HOSTNAME;
  }

  return sanitized;
}

String normalize_device_path_identifier(const String &raw_identifier) {
  String identifier = raw_identifier;
  identifier.trim();
  identifier.toLowerCase();

  String sanitized;
  sanitized.reserve(identifier.length());
  bool previous_was_dash = false;
  for (size_t index = 0; index < identifier.length(); index++) {
    char character = identifier[index];
    bool is_alphanumeric = (character >= 'a' && character <= 'z')
      || (character >= '0' && character <= '9');
    if (is_alphanumeric || character == '_' || character == '-') {
      sanitized += character;
      previous_was_dash = false;
      continue;
    }

    if (!previous_was_dash && sanitized.length() > 0) {
      sanitized += '-';
      previous_was_dash = true;
    }
  }

  while (sanitized.startsWith("-")) {
    sanitized.remove(0, 1);
  }
  while (sanitized.endsWith("-")) {
    sanitized.remove(sanitized.length() - 1);
  }
  if (sanitized.length() > 63) {
    sanitized.remove(63);
  }
  return sanitized;
}

bool is_valid_device_path_identifier(const char *identifier) {
  if (!identifier || identifier[0] == '\0') return false;

  size_t length = strlen(identifier);
  if (length == 0 || length > 64) return false;
  for (size_t index = 0; index < length; index++) {
    char character = identifier[index];
    bool is_alphanumeric = (character >= 'a' && character <= 'z')
      || (character >= 'A' && character <= 'Z')
      || (character >= '0' && character <= '9');
    if (is_alphanumeric || character == '_' || character == '-') continue;
    return false;
  }
  return true;
}

bool load_identity_api_key(char *buffer, size_t capacity) {
  if (!buffer || capacity == 0) return false;

  IdentityStringQuery query = {
    .buffer = buffer,
    .capacity = capacity,
    .ok = false,
  };
  if (!services::identity::accessAPIKey(&query)) return false;
  return query.ok && buffer[0] != '\0';
}

void normalize_config(const networking::tunnel::Config &input,
                      networking::tunnel::Config *output) {
  if (!output) return;
  memset(output, 0, sizeof(*output));

  output->enabled = input.enabled;
  output->provider = input.provider;
  output->local_port = input.local_port > 0 ? input.local_port : config::tunnel::LOCAL_PORT;
  output->reconnect = input.reconnect;

  String normalized_host = trim_and_strip_trailing_slashes(input.host);
  strlcpy(output->host, normalized_host.c_str(), sizeof(output->host));

  String normalized_path = input.path;
  normalized_path.trim();
  while (normalized_path.startsWith("/")) {
    normalized_path.remove(0, 1);
  }
  while (normalized_path.endsWith("/")) {
    normalized_path.remove(normalized_path.length() - 1);
  }
  if (!normalized_path.length()) {
    normalized_path = derive_default_device_path();
  } else {
    normalized_path = normalize_device_path_identifier(normalized_path);
    if (!normalized_path.length()) {
      normalized_path = derive_default_device_path();
    }
  }
  strlcpy(output->path, normalized_path.c_str(), sizeof(output->path));
}

void configure_default_config() {
  networking::tunnel::Config defaults = {};
  defaults.enabled = true;
  defaults.provider = networking::tunnel::ProviderSelfHosted;
  defaults.host[0] = '\0';
  defaults.local_port = config::tunnel::LOCAL_PORT;
  defaults.path[0] = '\0';
  defaults.reconnect = true;
  normalize_config(defaults, &state.config);
}

bool open_preferences(bool readonly, Preferences *preferences) {
  return services::preferences::open(config::tunnel::NVS_NAMESPACE, readonly, preferences);
}

bool load_persisted_config() {
  Preferences preferences;
  if (!open_preferences(true, &preferences)) return false;

  networking::tunnel::Config loaded = {};
  loaded.enabled = preferences.getBool("enabled", true);
  loaded.provider = static_cast<networking::tunnel::Provider>(
    preferences.getUChar("provider", static_cast<uint8_t>(networking::tunnel::ProviderSelfHosted))
  );
  preferences.getString("host", loaded.host, sizeof(loaded.host));
  loaded.local_port = preferences.getUShort("local_port", config::tunnel::LOCAL_PORT);
  preferences.getString("path", loaded.path, sizeof(loaded.path));
  loaded.reconnect = preferences.getBool("reconnect", true);
  preferences.end();

  normalize_config(loaded, &state.config);
  return true;
}

void ensure_config_loaded() {
  if (state.config_loaded) return;
  configure_default_config();
  load_persisted_config();
  state.config_loaded = true;
}

bool is_self_hosted_configured(const networking::tunnel::Config &config) {
  return config.host[0] != '\0' && config.path[0] != '\0';
}

networking::tunnel::Provider resolve_preferred_provider() {
  if (!state.config.enabled) return networking::tunnel::ProviderDisabled;

  if (state.config.provider == networking::tunnel::ProviderSelfHosted) {
    if (is_self_hosted_configured(state.config)) {
      return networking::tunnel::ProviderSelfHosted;
    }
    return networking::tunnel::ProviderBore;
  }

  if (state.config.provider == networking::tunnel::ProviderBore) {
    return networking::tunnel::ProviderBore;
  }

  return networking::tunnel::ProviderDisabled;
}

void set_phase(networking::tunnel::Phase phase) {
  state.phase = phase;
  state.snapshot.phase = phase;
}

void reset_runtime_for_start() {
  clear_snapshot_runtime_fields();
  state.snapshot.enabled = state.config.enabled;
  state.snapshot.provider = resolve_preferred_provider();
  state.snapshot.stopped = false;
  state.snapshot.started = true;
  state.snapshot.ready = false;
  state.backoff = kReconnectBackoffInitialMilliseconds;
  state.wait_until = 0;
  state.snapshot.backoff_ms = state.backoff;
  snprintf(state.snapshot.url, sizeof(state.snapshot.url), "(connecting...)");
  set_phase(networking::tunnel::PhaseInit);
}

void configure_keepalive(WiFiClient &client) {
  int file_descriptor = client.fd();
  if (file_descriptor < 0) {
    client.setNoDelay(true);
    return;
  }

  int enabled = 1;
  int idle = 10;
  int interval = 10;
  int count = 3;
  setsockopt(file_descriptor, SOL_SOCKET, SO_KEEPALIVE, &enabled, sizeof(enabled));
  setsockopt(file_descriptor, IPPROTO_TCP, TCP_KEEPIDLE, &idle, sizeof(idle));
  setsockopt(file_descriptor, IPPROTO_TCP, TCP_KEEPINTVL, &interval, sizeof(interval));
  setsockopt(file_descriptor, IPPROTO_TCP, TCP_KEEPCNT, &count, sizeof(count));
  setsockopt(file_descriptor, IPPROTO_TCP, TCP_NODELAY, &enabled, sizeof(enabled));
  client.setNoDelay(true);
}

bool connect_to_host(WiFiClient &client, const char *host, uint16_t port) {
  return host && host[0] != '\0' && client.connect(host, port, config::tunnel::CONNECT_MS);
}

bool connect_to_local(WiFiClient &client) {
  return client.connect(IPAddress(127, 0, 0, 1), state.config.local_port, config::tunnel::LOCAL_TIMEOUT_MS);
}

String receive_null_delimited_message(WiFiClient &client, int timeout_milliseconds = 5000) {
  String message;
  message.reserve(128);
  unsigned long started_at = millis();
  while (millis() - started_at < static_cast<unsigned long>(timeout_milliseconds)) {
    if (!client.connected()) return "";
    if (!client.available()) {
      delay_short();
      continue;
    }

    char character = client.read();
    if (character == '\0') return message;
    message += character;
    if (message.length() > 256) return "";
  }
  return "";
}

void send_null_delimited_message(WiFiClient &client, const String &message) {
  client.print(message);
  client.write(static_cast<uint8_t>(0));
}

int parse_hello_port(const String &message) {
  int position = message.indexOf("\"Hello\"");
  if (position < 0) return -1;
  position += 7;
  while (position < static_cast<int>(message.length())
         && (message[position] == ':' || message[position] == ' ')) {
    position++;
  }
  return atoi(message.c_str() + position);
}

String parse_connection_uuid(const String &message) {
  int position = message.indexOf("\"Connection\"");
  if (position < 0) return "";
  position += 12;
  while (position < static_cast<int>(message.length())
         && (message[position] == ':' || message[position] == ' ')) {
    position++;
  }
  if (position >= static_cast<int>(message.length()) || message[position] != '"') return "";

  position++;
  int start = position;
  while (position < static_cast<int>(message.length()) && message[position] != '"') {
    position++;
  }
  return message.substring(start, position);
}

String parse_error(const String &message) {
  int position = message.indexOf("\"Error\"");
  if (position < 0) return "";
  position += 7;
  while (position < static_cast<int>(message.length())
         && (message[position] == ':' || message[position] == ' ')) {
    position++;
  }
  if (position >= static_cast<int>(message.length()) || message[position] != '"') return "";

  position++;
  int start = position;
  while (position < static_cast<int>(message.length()) && message[position] != '"') {
    position++;
  }
  return message.substring(start, position);
}

int find_json_value_start(const String &json, const char *key) {
  const char *source = json.c_str();
  int key_length = strlen(key);
  const char *position = source;
  while ((position = strstr(position, key)) != nullptr) {
    if (position > source && *(position - 1) == '"' && *(position + key_length) == '"') {
      int index = static_cast<int>(position - source) + key_length + 1;
      while (index < static_cast<int>(json.length()) && (source[index] == ':' || source[index] == ' ')) {
        index++;
      }
      return index;
    }
    position++;
  }
  return -1;
}

String read_json_string(const String &json, const char *key) {
  int index = find_json_value_start(json, key);
  if (index < 0 || json[index] != '"') return "";

  index++;
  String result;
  while (index < static_cast<int>(json.length()) && json[index] != '"') {
    char character = json[index];
    if (character == '\\' && index + 1 < static_cast<int>(json.length())) {
      char escaped = json[++index];
      if (escaped == 'n') result += '\n';
      else if (escaped == 'r') result += '\r';
      else if (escaped == 't') result += '\t';
      else result += escaped;
    } else {
      result += character;
    }
    index++;
  }
  return result;
}

String escape_json_string(const String &value) {
  String escaped;
  escaped.reserve(value.length() + 16);
  for (size_t index = 0; index < value.length(); index++) {
    char character = value[index];
    if (character == '"' || character == '\\') {
      escaped += '\\';
      escaped += character;
      continue;
    }
    if (static_cast<uint8_t>(character) < 0x20) {
      char buffer[7] = {};
      snprintf(buffer, sizeof(buffer), "\\u%04x", static_cast<uint8_t>(character));
      escaped += buffer;
      continue;
    }
    escaped += character;
  }
  return escaped;
}

int read_line_into_buffer(WiFiClient &client, char *buffer, int capacity, int timeout_milliseconds) {
  int position = 0;
  unsigned long started_at = millis();
  while (position < capacity - 1 && millis() - started_at < static_cast<unsigned long>(timeout_milliseconds)) {
    if (!client.available()) {
      delay_short();
      continue;
    }

    char character = client.read();
    if (character == '\n') break;
    if (character != '\r') {
      buffer[position++] = character;
    }
  }
  buffer[position] = '\0';
  return position;
}

bool header_matches(const char *header, const char *prefix) {
  return strncasecmp(header, prefix, strlen(prefix)) == 0;
}

void write_forward_headers(WiFiClient &local_client, const String &message) {
  int index = find_json_value_start(message, "hdrs");
  if (index < 0 || message[index] != '{') return;

  index++;
  const char *source = message.c_str();
  int length = message.length();
  while (index < length && source[index] != '}') {
    while (index < length && (source[index] == ' ' || source[index] == ',' || source[index] == '\n')) {
      index++;
    }
    if (index >= length || source[index] == '}') break;
    if (source[index] != '"') {
      index++;
      continue;
    }

    index++;
    int key_start = index;
    while (index < length && source[index] != '"') index++;
    int key_end = index;
    index++;
    while (index < length && (source[index] == ':' || source[index] == ' ')) index++;
    if (index >= length || source[index] != '"') continue;

    index++;
    int value_start = index;
    while (index < length && source[index] != '"') {
      if (source[index] == '\\' && index + 1 < length) index += 2;
      else index++;
    }
    int value_end = index;
    index++;

    if (key_end > key_start && value_end > value_start) {
      local_client.write(reinterpret_cast<const uint8_t *>(source + key_start), key_end - key_start);
      local_client.write(reinterpret_cast<const uint8_t *>(": "), 2);
      local_client.write(reinterpret_cast<const uint8_t *>(source + value_start), value_end - value_start);
      local_client.write(reinterpret_cast<const uint8_t *>("\r\n"), 2);
    }
  }
}

bool open_local_http(WiFiClient &local_client, const String &method, const String &path,
                     const String &ip_address, const String &body, const String &content_type,
                     const String &raw_message) {
  if (!connect_to_local(local_client)) return false;

  local_client.setNoDelay(true);
  local_client.printf(
    "%s %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\nX-Forwarded-For: %s\r\n",
    method.c_str(),
    path.c_str(),
    ip_address.c_str()
  );
  write_forward_headers(local_client, raw_message);
  if (body.length()) {
    local_client.printf(
      "Content-Type: %s\r\nContent-Length: %d\r\n",
      content_type.length() ? content_type.c_str() : "text/plain",
      static_cast<int>(body.length())
    );
  }
  local_client.print("\r\n");
  if (body.length()) {
    local_client.print(body);
  }
  return true;
}

bool wait_for_local_http(WiFiClient &local_client) {
  unsigned long started_at = millis();
  while (!local_client.available() && local_client.connected()
         && millis() - started_at < config::tunnel::LOCAL_TIMEOUT_MS) {
    delay_short();
  }
  return local_client.available();
}

void parse_local_http_response(WiFiClient &local_client, int *status_code,
                               String *content_type, int *content_length) {
  char line[256] = {};
  read_line_into_buffer(local_client, line, sizeof(line), config::tunnel::LOCAL_TIMEOUT_MS);

  *status_code = 200;
  char *space = strchr(line, ' ');
  if (space) {
    *status_code = atoi(space + 1);
  }
  if (*status_code == 0) {
    *status_code = 200;
  }

  *content_type = "text/html";
  *content_length = -1;
  int header_bytes = 0;
  while (local_client.connected() && header_bytes < kMaximumHeaderSize) {
    if (!local_client.available()) {
      delay_short();
      continue;
    }

    int line_length = read_line_into_buffer(local_client, line, sizeof(line), kDrainTimeoutMilliseconds);
    header_bytes += line_length;
    if (line_length == 0) break;
    if (header_matches(line, "content-type:")) {
      *content_type = String(line + 13);
      content_type->trim();
    }
    if (header_matches(line, "content-length:")) {
      *content_length = atoi(line + 15);
    }
  }
}

String read_local_http_body(WiFiClient &local_client, int content_length) {
  int maximum_read = content_length > 0
    ? min(content_length, kMaximumBodySize)
    : kMaximumBodySize;

  String body;
  body.reserve(maximum_read > 0 ? maximum_read : 256);
  uint8_t buffer[256] = {};
  int bytes_read = 0;
  unsigned long last_read_at = millis();
  while (bytes_read < maximum_read && millis() - last_read_at < config::tunnel::LOCAL_TIMEOUT_MS) {
    if (local_client.available()) {
      int chunk = min(local_client.available(), min(static_cast<int>(sizeof(buffer)), maximum_read - bytes_read));
      int received = local_client.read(buffer, chunk);
      if (received > 0) {
        body.concat(reinterpret_cast<const char *>(buffer), received);
        bytes_read += received;
        last_read_at = millis();
      }
      continue;
    }

    if (!local_client.connected()) break;
    delay_short();
  }

  return body;
}

bool parse_self_hosted_endpoint(const char *configured_host) {
  String origin = trim_and_strip_trailing_slashes(configured_host);
  if (!origin.length()) return false;

  state.self_hosted.use_tls = false;
  if (origin.startsWith("https://")) {
    state.self_hosted.use_tls = true;
    origin.remove(0, 8);
  } else if (origin.startsWith("http://")) {
    origin.remove(0, 7);
  }

  int slash_index = origin.indexOf('/');
  if (slash_index >= 0) {
    origin.remove(slash_index);
  }

  int colon_index = origin.indexOf(':');
  state.self_hosted.relay_port = state.self_hosted.use_tls ? 443 : 80;
  if (colon_index >= 0) {
    state.self_hosted.relay_host = origin.substring(0, colon_index);
    state.self_hosted.relay_port = static_cast<uint16_t>(origin.substring(colon_index + 1).toInt());
  } else {
    state.self_hosted.relay_host = origin;
  }

  if (!state.self_hosted.relay_host.length() || state.self_hosted.relay_port == 0) return false;

  state.self_hosted.device_path = state.config.path;
  state.self_hosted.origin = state.self_hosted.use_tls ? "https://" : "http://";
  state.self_hosted.origin += state.self_hosted.relay_host;
  if ((state.self_hosted.use_tls && state.self_hosted.relay_port != 443)
      || (!state.self_hosted.use_tls && state.self_hosted.relay_port != 80)) {
    state.self_hosted.origin += ":";
    state.self_hosted.origin += String(state.self_hosted.relay_port);
  }
  return true;
}

String receive_websocket_message() {
  if (!state.self_hosted.websocket) return "";

  uint8_t first_byte = 0;
  uint8_t second_byte = 0;
  int opcode = 0;
  for (;;) {
    if (!state.self_hosted.websocket->connected() || !state.self_hosted.websocket->available()) return "";
    first_byte = state.self_hosted.websocket->read();
    second_byte = state.self_hosted.websocket->read();
    opcode = first_byte & 0x0F;

    if (opcode == 0x08) return "";
    if (opcode == 0x09) {
      int payload_length = second_byte & 0x7F;
      uint8_t pong_header[6] = {0x8A, static_cast<uint8_t>(payload_length | 0x80), 0, 0, 0, 0};
      state.self_hosted.websocket->write(pong_header, 6);
      for (int index = 0; index < payload_length; index++) {
        state.self_hosted.websocket->write(static_cast<uint8_t>(state.self_hosted.websocket->read()));
      }
      continue;
    }
    if (opcode == 0x0A) {
      for (int index = 0, payload_length = second_byte & 0x7F; index < payload_length; index++) {
        state.self_hosted.websocket->read();
      }
      continue;
    }
    break;
  }

  bool masked = (second_byte & 0x80) != 0;
  int payload_length = second_byte & 0x7F;
  if (payload_length == 126) {
    payload_length = (state.self_hosted.websocket->read() << 8) | state.self_hosted.websocket->read();
  } else if (payload_length == 127) {
    uint32_t high = 0;
    uint32_t low = 0;
    for (int index = 0; index < 4; index++) high = (high << 8) | state.self_hosted.websocket->read();
    for (int index = 0; index < 4; index++) low = (low << 8) | state.self_hosted.websocket->read();
    payload_length = (high == 0 && low <= static_cast<uint32_t>(kMaximumBodySize))
      ? static_cast<int>(low)
      : 0;
  }
  if (payload_length <= 0 || payload_length > kMaximumBodySize) return "";

  uint8_t mask[4] = {0};
  if (masked) {
    for (int index = 0; index < 4; index++) {
      mask[index] = state.self_hosted.websocket->read();
    }
  }

  String message;
  message.reserve(payload_length);
  uint8_t buffer[256] = {};
  int received_bytes = 0;
  unsigned long last_read_at = millis();
  while (received_bytes < payload_length
         && state.self_hosted.websocket->connected()
         && millis() - last_read_at < config::tunnel::PROXY_IDLE_MS) {
    int available_bytes = state.self_hosted.websocket->available();
    if (!available_bytes) {
      delay_short();
      continue;
    }

    int chunk = min(available_bytes, min(static_cast<int>(sizeof(buffer)), payload_length - received_bytes));
    int read_count = state.self_hosted.websocket->read(buffer, chunk);
    if (read_count <= 0) continue;

    if (masked) {
      for (int index = 0; index < read_count; index++) {
        buffer[index] ^= mask[(received_bytes + index) & 3];
      }
    }
    message.concat(reinterpret_cast<const char *>(buffer), read_count);
    received_bytes += read_count;
    last_read_at = millis();
  }

  return message;
}

bool begin_websocket_frame(int payload_length) {
  if (!state.self_hosted.websocket || !state.self_hosted.websocket->connected()) return false;

  uint8_t header[14] = {};
  int header_length = 0;
  header[header_length++] = 0x81;
  if (payload_length < 126) {
    header[header_length++] = static_cast<uint8_t>(payload_length | 0x80);
  } else if (payload_length <= 65535) {
    header[header_length++] = static_cast<uint8_t>(126 | 0x80);
    header[header_length++] = (payload_length >> 8) & 0xFF;
    header[header_length++] = payload_length & 0xFF;
  } else {
    header[header_length++] = static_cast<uint8_t>(127 | 0x80);
    header[header_length++] = 0;
    header[header_length++] = 0;
    header[header_length++] = 0;
    header[header_length++] = 0;
    header[header_length++] = (payload_length >> 24) & 0xFF;
    header[header_length++] = (payload_length >> 16) & 0xFF;
    header[header_length++] = (payload_length >> 8) & 0xFF;
    header[header_length++] = payload_length & 0xFF;
  }

  header[header_length++] = 0;
  header[header_length++] = 0;
  header[header_length++] = 0;
  header[header_length++] = 0;
  return state.self_hosted.websocket->write(header, header_length) == header_length;
}

bool send_websocket_json(const String &json) {
  if (!begin_websocket_frame(json.length())) return false;
  state.self_hosted.websocket->print(json);
  state.self_hosted.websocket->flush();
  return true;
}

bool send_self_hosted_route_config() {
  char api_key[64] = {};
  if (!load_identity_api_key(api_key, sizeof(api_key))) return true;

  String payload = "{\"type\":\"config\",\"routes\":[{\"path\":\"/\",\"password\":\"";
  payload += escape_json_string(api_key);
  payload += "\"}]}";
  return send_websocket_json(payload);
}

void send_self_hosted_response(const String &request_id, int status_code,
                               const String &body, const String &content_type) {
  String payload = "{\"id\":\"" + request_id + "\",\"status\":" + String(status_code)
    + ",\"body\":\"" + escape_json_string(body) + "\",\"type\":\""
    + escape_json_string(content_type) + "\"}";
  send_websocket_json(payload);
}

void send_self_hosted_error(const String &request_id, int status_code, const char *message) {
  send_self_hosted_response(request_id, status_code, message ? message : "Tunnel error", "text/plain");
}

bool connect_self_hosted_websocket() {
  if (!parse_self_hosted_endpoint(state.config.host)) {
    record_error("invalid self-hosted endpoint");
    return false;
  }

  if (state.self_hosted.use_tls) {
    if (!state.self_hosted.secure_websocket) {
      state.self_hosted.secure_websocket = new WiFiClientSecure();
      state.self_hosted.secure_websocket->setInsecure();
    }
    state.self_hosted.websocket = state.self_hosted.secure_websocket;

    time_t now = 0;
    time(&now);
    if (now < 100000) {
      configTime(0, 0, config::sntp::SERVER_1, config::sntp::SERVER_2);
      unsigned long started_at = millis();
      while (now < 100000 && millis() - started_at < config::sntp::SYNC_TIMEOUT_MS) {
        time(&now);
        vTaskDelay(pdMS_TO_TICKS(100));
      }
    }
  } else {
    state.self_hosted.websocket = &state.self_hosted.plain_websocket;
  }

  if (!connect_to_host(*state.self_hosted.websocket,
                       state.self_hosted.relay_host.c_str(),
                       state.self_hosted.relay_port)) {
    record_error("self-hosted websocket connect failed");
    return false;
  }

  state.self_hosted.websocket->printf(
    "GET %s?id=%s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
    "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n",
    config::tunnel::WS_PATH,
    state.self_hosted.device_path.c_str(),
    state.self_hosted.relay_host.c_str()
  );

  unsigned long started_at = millis();
  while (!state.self_hosted.websocket->available()
         && millis() - started_at < config::tunnel::CONNECT_MS) {
    vTaskDelay(pdMS_TO_TICKS(10));
  }
  if (!state.self_hosted.websocket->available()) {
    state.self_hosted.websocket->stop();
    record_error("self-hosted handshake timeout");
    return false;
  }

  char line[128] = {};
  read_line_into_buffer(*state.self_hosted.websocket, line, sizeof(line), config::tunnel::CONNECT_MS);
  if (!strstr(line, "101")) {
    state.self_hosted.websocket->stop();
    record_error("self-hosted handshake rejected");
    return false;
  }

  while (state.self_hosted.websocket->connected()) {
    int line_length = read_line_into_buffer(*state.self_hosted.websocket, line, sizeof(line), kDrainTimeoutMilliseconds);
    if (line_length == 0) break;
  }

  if (!send_self_hosted_route_config()) {
    state.self_hosted.websocket->stop();
    record_error("self-hosted route config failed");
    return false;
  }

  configure_keepalive(*state.self_hosted.websocket);
  state.self_hosted.last_ping_at = millis();
  snprintf(state.snapshot.url, sizeof(state.snapshot.url), "%s/%s",
           state.self_hosted.origin.c_str(), state.self_hosted.device_path.c_str());
  state.snapshot.ready = true;
  return true;
}

void parse_self_hosted_request(const String &message, String *request_id,
                               String *method, String *path, String *ip_address) {
  if (request_id) *request_id = read_json_string(message, "id");
  if (method) *method = read_json_string(message, "method");
  if (path) *path = read_json_string(message, "path");
  if (ip_address) *ip_address = read_json_string(message, "ip");
}

bool serve_self_hosted_connection() {
  if (!state.self_hosted.websocket || !state.self_hosted.websocket->connected()) return false;

  if (millis() - state.self_hosted.last_ping_at > kSelfHostedPingIntervalMilliseconds) {
    state.self_hosted.last_ping_at = millis();
    uint8_t ping_frame[6] = {0x89, 0x80, 0, 0, 0, 0};
    state.self_hosted.websocket->write(ping_frame, 6);
  }

  String message = receive_websocket_message();
  if (!message.length()) return state.self_hosted.websocket->connected();

  String request_id;
  String method;
  String path;
  String ip_address;
  parse_self_hosted_request(message, &request_id, &method, &path, &ip_address);
  if (!request_id.length() || !method.length()) return true;

  if (!path.length()) path = "/";
  if (path.indexOf("..") >= 0) {
    send_self_hosted_error(request_id, 400, "Bad path");
    return true;
  }

  String body;
  String content_type;
  if (method == "POST" || method == "PUT" || method == "PATCH") {
    body = read_json_string(message, "body");
    content_type = read_json_string(message, "ct");
  }

  strlcpy(state.snapshot.last_client_ip, ip_address.c_str(), sizeof(state.snapshot.last_client_ip));
  if (state.self_hosted.local_http.connected()) {
    state.self_hosted.local_http.stop();
  }

  if (!open_local_http(state.self_hosted.local_http, method, path, ip_address, body, content_type, message)) {
    send_self_hosted_error(request_id, 502, "Local server unreachable");
    return true;
  }
  if (!wait_for_local_http(state.self_hosted.local_http)) {
    state.self_hosted.local_http.stop();
    send_self_hosted_error(request_id, 504, "Local timeout");
    return true;
  }

  int status_code = 200;
  String response_content_type;
  int response_content_length = -1;
  parse_local_http_response(state.self_hosted.local_http, &status_code, &response_content_type, &response_content_length);
  String response_body = read_local_http_body(state.self_hosted.local_http, response_content_length);
  state.self_hosted.local_http.stop();
  send_self_hosted_response(request_id, status_code, response_body, response_content_type);
  return true;
}

void stop_self_hosted() {
  if (state.self_hosted.websocket) {
    state.self_hosted.websocket->stop();
  }
  state.self_hosted.local_http.stop();
  if (state.self_hosted.secure_websocket) {
    delete state.self_hosted.secure_websocket;
    state.self_hosted.secure_websocket = nullptr;
  }
  state.self_hosted.websocket = nullptr;
  state.self_hosted.origin = "";
  state.self_hosted.relay_host = "";
  state.self_hosted.device_path = "";
  state.self_hosted.relay_port = 0;
  state.self_hosted.use_tls = false;
  state.self_hosted.last_ping_at = 0;
}

void proxy_bore_bytes(WiFiClient &remote, WiFiClient &local) {
  uint8_t buffer[512] = {};
  unsigned long last_activity = millis();
  while (remote.connected() && local.connected()
         && millis() - last_activity < config::tunnel::PROXY_IDLE_MS) {
    bool has_activity = false;
    if (remote.available()) {
      int bytes_read = remote.read(buffer, sizeof(buffer));
      if (bytes_read > 0) {
        local.write(buffer, bytes_read);
        has_activity = true;
      }
    }
    if (local.available()) {
      int bytes_read = local.read(buffer, sizeof(buffer));
      if (bytes_read > 0) {
        remote.write(buffer, bytes_read);
        has_activity = true;
      }
    }
    if (has_activity) {
      last_activity = millis();
    } else {
      delay_short();
    }
  }
  remote.stop();
  local.stop();
}

const char *access_bore_host() {
  if (state.config.provider == networking::tunnel::ProviderBore && state.config.host[0] != '\0') {
    return state.config.host;
  }
  return config::tunnel::BORE_HOST;
}

void accept_bore_connection(const String &uuid, int slot) {
  WiFiClient &proxy_connection = bore_proxy_connections[slot];
  WiFiClient &local_connection = bore_local_connections[slot];

  if (!connect_to_host(proxy_connection, access_bore_host(), kBoreControlPort)) return;
  send_null_delimited_message(proxy_connection, "{\"Accept\":\"" + uuid + "\"}");

  if (!connect_to_local(local_connection)) {
    proxy_connection.stop();
    return;
  }
  local_connection.setNoDelay(true);
  proxy_bore_bytes(proxy_connection, local_connection);
}

bool initialize_bore() {
  if (WiFi.status() != WL_CONNECTED) return false;
  if (bore_control_connection.connected()) {
    bore_control_connection.stop();
  }

  if (!connect_to_host(bore_control_connection, access_bore_host(), kBoreControlPort)) {
    record_error("bore control connection failed");
    return false;
  }
  configure_keepalive(bore_control_connection);
  send_null_delimited_message(bore_control_connection, "{\"Hello\":0}");

  String response = receive_null_delimited_message(bore_control_connection, 10000);
  if (!response.length()) {
    bore_control_connection.stop();
    record_error("bore hello timeout");
    return false;
  }

  String error = parse_error(response);
  if (error.length()) {
    bore_control_connection.stop();
    record_error(error.c_str());
    return false;
  }

  int port = parse_hello_port(response);
  if (port <= 0) {
    bore_control_connection.stop();
    record_error("bore hello response invalid");
    return false;
  }

  state.snapshot.remote_port = static_cast<uint16_t>(port);
  snprintf(state.snapshot.url, sizeof(state.snapshot.url), "http://%s:%d", access_bore_host(), port);
  state.snapshot.ready = true;
  return true;
}

bool serve_bore_connection() {
  if (!bore_control_connection.connected()) return false;
  if (!bore_control_connection.available()) return true;

  String message = receive_null_delimited_message(bore_control_connection, 3000);
  if (!message.length()) return bore_control_connection.connected();
  if (message.indexOf("\"Heartbeat\"") >= 0) return true;

  String uuid = parse_connection_uuid(message);
  if (!uuid.length()) return true;

  int slot = -1;
  for (int index = 0; index < kMaximumProxyConnections; index++) {
    if (!bore_proxy_connections[index].connected() && !bore_local_connections[index].connected()) {
      slot = index;
      break;
    }
  }
  if (slot < 0) return true;

  accept_bore_connection(uuid, slot);
  return true;
}

void stop_bore() {
  bore_control_connection.stop();
  for (int index = 0; index < kMaximumProxyConnections; index++) {
    bore_proxy_connections[index].stop();
    bore_local_connections[index].stop();
  }
}

bool initialize_active_provider() {
  networking::tunnel::Provider preferred_provider = resolve_preferred_provider();
  if (preferred_provider == networking::tunnel::ProviderDisabled) {
    record_error("tunnel disabled");
    return false;
  }

  if (preferred_provider == networking::tunnel::ProviderSelfHosted) {
    state.snapshot.provider = networking::tunnel::ProviderSelfHosted;
    if (connect_self_hosted_websocket()) {
      return true;
    }

    state.snapshot.provider = networking::tunnel::ProviderBore;
    if (initialize_bore()) {
      return true;
    }
    return false;
  }

  state.snapshot.provider = networking::tunnel::ProviderBore;
  return initialize_bore();
}

bool serve_active_provider() {
  switch (state.snapshot.provider) {
    case networking::tunnel::ProviderSelfHosted:
      return serve_self_hosted_connection();
    case networking::tunnel::ProviderBore:
      return serve_bore_connection();
    default:
      return false;
  }
}

void stop_active_provider() {
  if (state.snapshot.provider == networking::tunnel::ProviderSelfHosted) {
    stop_self_hosted();
    return;
  }
  if (state.snapshot.provider == networking::tunnel::ProviderBore) {
    stop_bore();
  }
}

void halt_transport() {
  stop_active_provider();
  state.snapshot.started = false;
  state.snapshot.stopped = true;
  state.snapshot.ready = false;
  state.snapshot.remote_port = 0;
  set_phase(networking::tunnel::PhaseIdle);
  snprintf(state.snapshot.url, sizeof(state.snapshot.url), "(stopped)");
}

void run_state_machine() {
  if (!state.snapshot.started || state.snapshot.stopped) return;

  switch (state.phase) {
    case networking::tunnel::PhaseIdle:
      break;
    case networking::tunnel::PhaseInit:
      state.snapshot.connect_attempts++;
      if (initialize_active_provider()) {
        set_phase(networking::tunnel::PhaseServe);
        state.backoff = kReconnectBackoffInitialMilliseconds;
      } else {
        if (!state.config.reconnect) {
          halt_transport();
          break;
        }
        set_phase(networking::tunnel::PhaseWait);
        state.wait_until = millis() + state.backoff;
        state.backoff = min(state.backoff * 2, kReconnectBackoffMaximumMilliseconds);
      }
      state.snapshot.backoff_ms = state.backoff;
      break;
    case networking::tunnel::PhaseServe:
      if (!serve_active_provider()) {
        if (!state.config.reconnect) {
          halt_transport();
          break;
        }
        stop_active_provider();
        state.snapshot.ready = false;
        set_phase(networking::tunnel::PhaseWait);
        state.wait_until = millis() + state.backoff;
        state.backoff = min(state.backoff * 2, kReconnectBackoffMaximumMilliseconds);
        state.snapshot.backoff_ms = state.backoff;
      }
      break;
    case networking::tunnel::PhaseWait:
      if (millis() >= state.wait_until) {
        set_phase(networking::tunnel::PhaseInit);
      }
      break;
  }
}

} // namespace

void networking::tunnel::initialize() {
  ensure_config_loaded();
  if (state.snapshot.started) return;

  state.snapshot.enabled = state.config.enabled;
  if (!state.config.enabled) {
    state.snapshot.provider = ProviderDisabled;
    state.snapshot.stopped = true;
    state.snapshot.phase = PhaseIdle;
    snprintf(state.snapshot.url, sizeof(state.snapshot.url), "(disabled)");
    return;
  }

  reset_runtime_for_start();
  Serial.printf("[tunnel] starting via %s\n", provider_name(state.snapshot.provider));
}

void networking::tunnel::service() {
  ensure_config_loaded();
  if (!state.config.enabled || !state.snapshot.started) return;
  run_state_machine();
}

void networking::tunnel::stop() {
  if (!state.snapshot.started && !state.snapshot.ready) return;
  stop_active_provider();
  state.snapshot.started = false;
  state.snapshot.stopped = true;
  state.snapshot.ready = false;
  state.snapshot.remote_port = 0;
  state.snapshot.phase = PhaseIdle;
  state.snapshot.backoff_ms = state.backoff;
  snprintf(state.snapshot.url, sizeof(state.snapshot.url), "(stopped)");
}

bool networking::tunnel::isReady() {
  return state.snapshot.ready;
}

bool networking::tunnel::isStarted() {
  return state.snapshot.started;
}

const char *networking::tunnel::accessURL() {
  return state.snapshot.url;
}

const char *networking::tunnel::accessProviderName() {
  return provider_name(state.snapshot.provider);
}

const char *networking::tunnel::accessLastClientIP() {
  return state.snapshot.last_client_ip[0] ? state.snapshot.last_client_ip : "";
}

void networking::tunnel::configure(const Config &config) {
  ensure_config_loaded();
  Config normalized = {};
  normalize_config(config, &normalized);
  state.config = normalized;
  state.snapshot.enabled = state.config.enabled;

  bool should_restart = state.snapshot.started || state.snapshot.ready;
  if (should_restart) {
    stop();
  }

  if (state.config.enabled) {
    initialize();
  } else {
    state.snapshot.provider = ProviderDisabled;
    state.snapshot.stopped = true;
    state.snapshot.phase = PhaseIdle;
    snprintf(state.snapshot.url, sizeof(state.snapshot.url), "(disabled)");
  }
}

void networking::tunnel::accessConfig(Config &config) {
  ensure_config_loaded();
  config = state.config;
}

bool networking::tunnel::storeConfig(Config *config) {
  if (!config) return false;

  Config normalized = {};
  normalize_config(*config, &normalized);
  if (normalized.provider == ProviderSelfHosted && !is_valid_device_path_identifier(normalized.path)) {
    record_error("invalid self-hosted path");
    return false;
  }

  Preferences preferences;
  if (!open_preferences(false, &preferences)) return false;
  preferences.putBool("enabled", normalized.enabled);
  preferences.putUChar("provider", static_cast<uint8_t>(normalized.provider));
  preferences.putString("host", normalized.host);
  preferences.putUShort("local_port", normalized.local_port);
  preferences.putString("path", normalized.path);
  preferences.putBool("reconnect", normalized.reconnect);
  preferences.end();

  *config = normalized;
  state.config = normalized;
  state.config_loaded = true;
  return true;
}

bool networking::tunnel::clearConfig() {
  Preferences preferences;
  if (!open_preferences(false, &preferences)) return false;
  preferences.clear();
  preferences.end();

  configure_default_config();
  state.config_loaded = true;
  return true;
}

void networking::tunnel::accessSnapshot(Snapshot &snapshot) {
  ensure_config_loaded();
  snapshot = state.snapshot;
  snapshot.phase = state.phase;
  snapshot.backoff_ms = state.backoff;
}

void networking::tunnel::enable() {
  ensure_config_loaded();
  state.config.enabled = true;
  state.snapshot.enabled = true;
  if (!state.snapshot.started) {
    initialize();
  }
}

void networking::tunnel::disable() {
  ensure_config_loaded();
  state.config.enabled = false;
  state.snapshot.enabled = false;
  stop();
  state.snapshot.provider = ProviderDisabled;
  snprintf(state.snapshot.url, sizeof(state.snapshot.url), "(disabled)");
}

#else

void networking::tunnel::initialize() {}
void networking::tunnel::service() {}
void networking::tunnel::stop() {}
bool networking::tunnel::isReady() { return false; }
bool networking::tunnel::isStarted() { return false; }
const char *networking::tunnel::accessURL() { return ""; }
const char *networking::tunnel::accessProviderName() { return "disabled"; }
const char *networking::tunnel::accessLastClientIP() { return ""; }
void networking::tunnel::configure(const Config &config) { (void)config; }
void networking::tunnel::accessConfig(Config &config) {
  memset(&config, 0, sizeof(config));
  config.local_port = config::tunnel::LOCAL_PORT;
}
bool networking::tunnel::storeConfig(Config *config) { return config != nullptr; }
bool networking::tunnel::clearConfig() { return true; }
void networking::tunnel::accessSnapshot(Snapshot &snapshot) {
  memset(&snapshot, 0, sizeof(snapshot));
  snapshot.provider = ProviderDisabled;
  snapshot.phase = PhaseIdle;
}
void networking::tunnel::enable() {}
void networking::tunnel::disable() {}

#endif

#ifdef PIO_UNIT_TESTING

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
  TEST_IGNORE_MESSAGE("tunnel is enabled - test not applicable");
#endif
}

static void test_tunnel_initialize_state(void) {
  WHEN("the tunnel is initialized");
  THEN("the snapshot reports the default startup state");

#if CERATINA_TUNNEL_ENABLED
  networking::tunnel::stop();
  networking::tunnel::clearConfig();
  networking::tunnel::initialize();

  networking::tunnel::Snapshot snapshot = {};
  networking::tunnel::accessSnapshot(snapshot);
  networking::tunnel::Config config = {};
  networking::tunnel::accessConfig(config);

  TEST_ASSERT_TRUE_MESSAGE(snapshot.enabled, "device: tunnel should be enabled after initialize");
  TEST_ASSERT_TRUE_MESSAGE(snapshot.started, "device: tunnel should be started after initialize");
  TEST_ASSERT_FALSE_MESSAGE(snapshot.stopped, "device: tunnel should not be stopped after initialize");
  TEST_ASSERT_FALSE_MESSAGE(snapshot.ready, "device: tunnel should not be ready before connect");
  TEST_ASSERT_EQUAL_UINT8_MESSAGE(networking::tunnel::ProviderSelfHosted, config.provider,
    "device: default configured provider should prefer self-hosted");
  TEST_ASSERT_TRUE_MESSAGE(snapshot.provider == networking::tunnel::ProviderSelfHosted
                           || snapshot.provider == networking::tunnel::ProviderBore,
    "device: active provider should be self-hosted or bore fallback");
  TEST_ASSERT_TRUE_MESSAGE(config.path[0] != '\0',
    "device: default tunnel path should be derived from device identity");
  TEST_ASSERT_EQUAL_UINT8_MESSAGE(networking::tunnel::PhaseInit, snapshot.phase,
    "device: tunnel should enter init phase after initialize");
#else
  TEST_IGNORE_MESSAGE("tunnel is disabled - test not applicable");
#endif
}

static void test_tunnel_stop_state(void) {
  WHEN("the tunnel is stopped");
  THEN("the snapshot reports the stopped state");

#if CERATINA_TUNNEL_ENABLED
  networking::tunnel::initialize();
  networking::tunnel::stop();

  networking::tunnel::Snapshot snapshot = {};
  networking::tunnel::accessSnapshot(snapshot);

  TEST_ASSERT_TRUE_MESSAGE(snapshot.stopped, "device: tunnel should report stopped after stop");
  TEST_ASSERT_FALSE_MESSAGE(snapshot.ready, "device: tunnel should not be ready after stop");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("(stopped)", snapshot.url,
    "device: tunnel should expose a stopped status after stop");
#else
  TEST_IGNORE_MESSAGE("tunnel is disabled - test not applicable");
#endif
}

static void test_tunnel_configure_preserves_provider(void) {
  WHEN("the tunnel is configured with a custom self-hosted endpoint");
  THEN("the config can be read back without being overwritten");

#if CERATINA_TUNNEL_ENABLED
  networking::tunnel::stop();

  networking::tunnel::Config expected = {};
  expected.enabled = true;
  expected.provider = networking::tunnel::ProviderSelfHosted;
  strlcpy(expected.host, "https://example.com", sizeof(expected.host));
  expected.local_port = 8080;
  strlcpy(expected.path, "device-demo", sizeof(expected.path));
  expected.reconnect = false;

  networking::tunnel::configure(expected);

  networking::tunnel::Config actual = {};
  networking::tunnel::accessConfig(actual);

  TEST_ASSERT_EQUAL_MESSAGE(expected.enabled, actual.enabled,
    "device: tunnel enabled flag should match the configured value");
  TEST_ASSERT_EQUAL_UINT8_MESSAGE(expected.provider, actual.provider,
    "device: tunnel provider should match the configured provider");
  TEST_ASSERT_EQUAL_STRING_MESSAGE(expected.host, actual.host,
    "device: tunnel host should match the configured host");
  TEST_ASSERT_EQUAL_UINT16_MESSAGE(expected.local_port, actual.local_port,
    "device: tunnel local port should match the configured port");
  TEST_ASSERT_EQUAL_STRING_MESSAGE(expected.path, actual.path,
    "device: tunnel path should match the configured path");
  TEST_ASSERT_EQUAL_MESSAGE(expected.reconnect, actual.reconnect,
    "device: tunnel reconnect policy should match the configured value");
#else
  TEST_IGNORE_MESSAGE("tunnel is disabled - test not applicable");
#endif
}

static void test_tunnel_store_config_roundtrip(void) {
  WHEN("tunnel config is stored to NVS");
  THEN("it can be read back with the same values");

#if CERATINA_TUNNEL_ENABLED
  networking::tunnel::Config written = {};
  written.enabled = true;
  written.provider = networking::tunnel::ProviderBore;
  strlcpy(written.host, "bore.pub", sizeof(written.host));
  written.local_port = 81;
  strlcpy(written.path, "device-test", sizeof(written.path));
  written.reconnect = true;

  TEST_ASSERT_TRUE_MESSAGE(networking::tunnel::storeConfig(&written),
    "device: tunnel config should be writable");

  networking::tunnel::Config read_back = {};
  networking::tunnel::accessConfig(read_back);
  TEST_ASSERT_EQUAL_MESSAGE(written.enabled, read_back.enabled,
    "device: enabled flag should survive tunnel config roundtrip");
  TEST_ASSERT_EQUAL_UINT8_MESSAGE(written.provider, read_back.provider,
    "device: provider should survive tunnel config roundtrip");
  TEST_ASSERT_EQUAL_STRING_MESSAGE(written.host, read_back.host,
    "device: host should survive tunnel config roundtrip");
  TEST_ASSERT_EQUAL_UINT16_MESSAGE(written.local_port, read_back.local_port,
    "device: local port should survive tunnel config roundtrip");
  TEST_ASSERT_EQUAL_STRING_MESSAGE(written.path, read_back.path,
    "device: path should survive tunnel config roundtrip");
  TEST_ASSERT_EQUAL_MESSAGE(written.reconnect, read_back.reconnect,
    "device: reconnect should survive tunnel config roundtrip");
#else
  TEST_IGNORE_MESSAGE("tunnel is disabled - test not applicable");
#endif
}

static void test_tunnel_path_is_normalized_for_relay(void) {
  WHEN("a self-hosted path contains spaces and punctuation");
  THEN("the stored path is normalized into a relay-safe identifier");

#if CERATINA_TUNNEL_ENABLED
  networking::tunnel::Config config = {};
  config.enabled = true;
  config.provider = networking::tunnel::ProviderSelfHosted;
  strlcpy(config.host, "https://relay.example.com", sizeof(config.host));
  strlcpy(config.path, "  My Field Device !!!  ", sizeof(config.path));
  config.local_port = 80;
  config.reconnect = true;

  TEST_ASSERT_TRUE_MESSAGE(networking::tunnel::storeConfig(&config),
    "device: self-hosted config should be storable after path normalization");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("my-field-device", config.path,
    "device: self-hosted path should be normalized into a relay-safe identifier");
#else
  TEST_IGNORE_MESSAGE("tunnel is disabled - test not applicable");
#endif
}

static void test_tunnel_self_hosted_without_host_falls_back_to_bore(void) {
  WHEN("self-hosted is selected without a relay host");
  THEN("the active provider falls back to bore during startup");

#if CERATINA_TUNNEL_ENABLED
  networking::tunnel::stop();

  networking::tunnel::Config config = {};
  config.enabled = true;
  config.provider = networking::tunnel::ProviderSelfHosted;
  config.host[0] = '\0';
  strlcpy(config.path, "field-node", sizeof(config.path));
  config.local_port = 80;
  config.reconnect = true;
  networking::tunnel::configure(config);

  networking::tunnel::Snapshot snapshot = {};
  networking::tunnel::accessSnapshot(snapshot);

  TEST_ASSERT_EQUAL_UINT8_MESSAGE(networking::tunnel::ProviderBore, snapshot.provider,
    "device: active provider should fall back to bore when self-hosted host is unset");
#else
  TEST_IGNORE_MESSAGE("tunnel is disabled - test not applicable");
#endif
}

void networking::tunnel::test(void) {
  MODULE("Tunnel");
  RUN_TEST(test_tunnel_config);
  RUN_TEST(test_tunnel_noop_when_disabled);
  RUN_TEST(test_tunnel_initialize_state);
  RUN_TEST(test_tunnel_stop_state);
  RUN_TEST(test_tunnel_configure_preserves_provider);
  RUN_TEST(test_tunnel_store_config_roundtrip);
  RUN_TEST(test_tunnel_path_is_normalized_for_relay);
  RUN_TEST(test_tunnel_self_hosted_without_host_falls_back_to_bore);
}

#endif
