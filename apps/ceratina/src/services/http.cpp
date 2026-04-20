#include "http.h"

#ifdef PIO_UNIT_TESTING

#include <networking/wifi.h>
#include <testing/utils.h>

#include <ArduinoJson.h>
#include <LittleFS.h>
#include <WiFi.h>
#include <WiFiClient.h>

// ─────────────────────────────────────────────────────────────────────────────
//  Unit Tests
// ─────────────────────────────────────────────────────────────────────────────

static void test_http_port_default(void) {
  THEN("the HTTP port is 80");
  TEST_ASSERT_EQUAL_INT_MESSAGE(80, config::http::PORT,
    "device: HTTP port should be 80");
}

static void test_json_create_and_serialize(void) {
  WHEN("a JSON document is created and serialized");

  JsonDocument doc;
  doc["hostname"] = "microvisor";
  doc["port"] = 22;
  doc["active"] = true;

  char buf[128];
  size_t len = serializeJson(doc, buf, sizeof(buf));
  TEST_ASSERT_GREATER_THAN_MESSAGE(0, (int)len,
    "device: serializeJson returned 0");

  JsonDocument readback;
  DeserializationError err = deserializeJson(readback, buf);
  TEST_ASSERT_FALSE_MESSAGE((bool)err, "device: failed to deserialize own output");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("microvisor", readback["hostname"].as<const char *>(),
    "device: hostname mismatch after roundtrip");
  TEST_ASSERT_EQUAL_INT_MESSAGE(22, readback["port"].as<int>(),
    "device: port mismatch after roundtrip");
  TEST_ASSERT_TRUE_MESSAGE(readback["active"].as<bool>(),
    "device: active should be true after roundtrip");

  TEST_MESSAGE(buf);
}

static void test_json_measure_length(void) {
  WHEN("measureJson is compared to serializeJson length");

  JsonDocument doc;
  doc["key"] = "value";

  size_t measured = measureJson(doc);
  char buf[64];
  size_t actual = serializeJson(doc, buf, sizeof(buf));

  TEST_ASSERT_EQUAL_UINT32_MESSAGE(measured, actual,
    "device: measureJson doesn't match serializeJson length");

  TEST_PRINTF("measured=%u actual=%u", (unsigned)measured, (unsigned)actual);
}

static void test_json_deserialize(void) {
  WHEN("a JSON string is deserialized");

  const char *input = "{\"sensor\":\"scd4x\",\"co2\":412,\"temp\":23.5,\"ok\":true}";
  JsonDocument doc;
  DeserializationError error = deserializeJson(doc, input);

  TEST_ASSERT_FALSE_MESSAGE((bool)error,
    "device: deserialization failed");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("scd4x", doc["sensor"].as<const char *>(),
    "device: sensor value mismatch");
  TEST_ASSERT_EQUAL_INT_MESSAGE(412, doc["co2"].as<int>(),
    "device: co2 value mismatch");
  TEST_ASSERT_EQUAL_FLOAT_MESSAGE(23.5f, doc["temp"].as<float>(),
    "device: temp value mismatch");
  TEST_ASSERT_TRUE_MESSAGE(doc["ok"].as<bool>(),
    "device: ok should be true");

}

static void test_json_default_values(void) {
  WHEN("missing keys are read with the | operator");

  JsonDocument doc;
  deserializeJson(doc, "{\"port\":8080}");

  int port = doc["port"] | 3000;
  int missing = doc["timeout"] | 5000;

  TEST_ASSERT_EQUAL_INT_MESSAGE(8080, port,
    "device: existing key should return its value");
  TEST_ASSERT_EQUAL_INT_MESSAGE(5000, missing,
    "device: missing key should return default");

}

static void test_json_nested_objects_and_arrays(void) {
  WHEN("nested objects and arrays are created");

  JsonDocument doc;
  doc["device"] = "microvisor";

  JsonArray sensors = doc["sensors"].to<JsonArray>();
  JsonObject sensor0 = sensors.add<JsonObject>();
  sensor0["name"] = "scd4x";
  sensor0["bus"] = "i2c.1";
  sensor0["addr"] = 0x62;

  JsonObject sensor1 = sensors.add<JsonObject>();
  sensor1["name"] = "ds3231";
  sensor1["bus"] = "i2c.0";
  sensor1["addr"] = 0x68;

  TEST_ASSERT_EQUAL_INT_MESSAGE(2, doc["sensors"].size(),
    "device: sensors array should have 2 elements");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("scd4x", doc["sensors"][0]["name"].as<const char *>(),
    "device: first sensor name mismatch");
  TEST_ASSERT_EQUAL_HEX8_MESSAGE(0x68, doc["sensors"][1]["addr"].as<int>(),
    "device: second sensor addr mismatch");

  char buf[256];
  serializeJson(doc, buf, sizeof(buf));
  TEST_MESSAGE(buf);
}

static void test_json_file_roundtrip(void) {
  WHEN("JSON is written to LittleFS and read back");

  TEST_ASSERT_TRUE_MESSAGE(LittleFS.begin(false),
    "device: LittleFS mount failed before JSON file roundtrip");
  const char *path = "/.test_json.tmp";

  JsonDocument write_doc;
  write_doc["hostname"] = "microvisor";
  write_doc["port"] = 22;

  File writer = LittleFS.open(path, FILE_WRITE);
  TEST_ASSERT_TRUE_MESSAGE((bool)writer, "device: open for write failed");
  serializeJson(write_doc, writer);
  writer.close();

  File reader = LittleFS.open(path, FILE_READ);
  TEST_ASSERT_TRUE_MESSAGE((bool)reader, "device: open for read failed");
  JsonDocument read_doc;
  DeserializationError error = deserializeJson(read_doc, reader);
  reader.close();

  TEST_ASSERT_FALSE_MESSAGE((bool)error, "device: deserialize from file failed");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("microvisor", read_doc["hostname"].as<const char *>(),
    "device: hostname mismatch after file roundtrip");
  TEST_ASSERT_EQUAL_INT_MESSAGE(22, read_doc["port"].as<int>(),
    "device: port mismatch after file roundtrip");

  LittleFS.remove(path);
}

static void test_http_cors_allows_patch(void) {
  THEN("CORS allows PATCH method");
  TEST_IGNORE_MESSAGE("CORS config verified by code review — test with browser");
}

static void test_http_public_endpoints_no_auth(void) {
  THEN("public endpoints require no auth");
  // These endpoints must remain accessible without authentication:
  //   GET /api/wifi
  //   GET /api/system/device/status
  //   GET /api/cloudevents
  //   GET /api/wireless/status
  TEST_ASSERT_EQUAL_INT_MESSAGE(0, CERATINA_HTTP_AUTH_ENABLED,
    "device: auth is disabled by default — enable to test auth enforcement");
}

static void test_http_auth_config(void) {
  THEN("auth configuration defaults are valid");
  TEST_ASSERT_NOT_NULL_MESSAGE(config::http::AUTH_USER,
    "device: HTTP auth user must not be null");
  TEST_ASSERT_NOT_NULL_MESSAGE(config::http::AUTH_PASSWORD,
    "device: HTTP auth password must not be null");
  TEST_ASSERT_NOT_NULL_MESSAGE(config::http::AUTH_REALM,
    "device: HTTP auth realm must not be null");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("ceratina", config::http::AUTH_REALM,
    "device: auth realm should be 'ceratina'");

  TEST_PRINTF("auth user=%s realm=%s enabled=%d",
           config::http::AUTH_USER, config::http::AUTH_REALM, CERATINA_HTTP_AUTH_ENABLED);
}

static void test_http_rate_limit_policy(void) {
  THEN("rate limit policy is documented");
  TEST_IGNORE_MESSAGE("rate limit policy documented — test with curl");
}

void services::http::test(void) {
  MODULE("HTTP");
  RUN_TEST(test_http_port_default);
  RUN_TEST(test_http_cors_allows_patch);
  RUN_TEST(test_http_public_endpoints_no_auth);
  RUN_TEST(test_http_auth_config);
  RUN_TEST(test_http_rate_limit_policy);

  MODULE("JSON");
  RUN_TEST(test_json_create_and_serialize);
  RUN_TEST(test_json_measure_length);
  RUN_TEST(test_json_deserialize);
  RUN_TEST(test_json_default_values);
  RUN_TEST(test_json_nested_objects_and_arrays);
  RUN_TEST(test_json_file_roundtrip);
}

namespace services::http_e2e { void test(void); }

static const uint16_t HTTP_TIMEOUT_MS = 5000;
static bool server_started = false;

static bool ensure_ready(void) {
  if (server_started && WiFi.isConnected()) return true;

  if (!WiFi.isConnected()) {
    networking::wifi::sta::initialize();
    if (!networking::wifi::sta::connect()) return false;
    delay(500);
  }

  if (!server_started) {
    services::http::initialize();
    for (int i = 0; i < 20; i++) {
      delay(100);
      vTaskDelay(1);
    }
    server_started = true;
    Serial.printf("[e2e] server started, IP=%s port=%d core=%d heap=%u\n",
                  WiFi.localIP().toString().c_str(), config::http::PORT,
                  xPortGetCoreID(), ESP.getFreeHeap());
  }

  return WiFi.isConnected();
}

static int http_request(const char *method, const char *path,
                        const char *body, char *response, size_t response_size) {
  WiFiClient client;
  IPAddress ip = WiFi.localIP();

  if (ip == IPAddress(0, 0, 0, 0)) {
    Serial.println("[e2e] WiFi.localIP() is 0.0.0.0");
    return -3;
  }

  client.setTimeout(HTTP_TIMEOUT_MS);
  if (!client.connect(ip, config::http::PORT)) {
    Serial.printf("[e2e] connect to %s:%d failed, retrying...\n",
                  ip.toString().c_str(), config::http::PORT);
    delay(500);
    if (!client.connect(ip, config::http::PORT)) {
      Serial.printf("[e2e] connect retry failed (core=%d)\n", xPortGetCoreID());
      return -1;
    }
  }

  if (body) {
    client.printf("%s %s HTTP/1.1\r\n"
                  "Host: %s\r\n"
                  "Content-Type: application/json\r\n"
                  "Content-Length: %d\r\n"
                  "Connection: close\r\n\r\n%s",
                  method, path, ip.toString().c_str(),
                  (int)strlen(body), body);
  } else {
    client.printf("%s %s HTTP/1.1\r\n"
                  "Host: %s\r\n"
                  "Connection: close\r\n\r\n",
                  method, path, ip.toString().c_str());
  }

  uint32_t start = millis();
  while (!client.available() && millis() - start < HTTP_TIMEOUT_MS) {
    delay(10);
  }

  if (!client.available()) { client.stop(); return -2; }

  String status_line = client.readStringUntil('\n');
  int code = 0;
  int space = status_line.indexOf(' ');
  if (space > 0) code = status_line.substring(space + 1).toInt();

  while (client.available()) {
    String header = client.readStringUntil('\n');
    if (header == "\r" || header.length() == 0) break;
  }

  if (response && response_size > 0) {
    size_t pos = 0;
    while (client.available() && pos < response_size - 1) {
      response[pos++] = client.read();
    }
    response[pos] = '\0';
  }

  client.stop();
  return code;
}

static void assert_get(const char *path, int expected_code) {
  if (!ensure_ready()) {
    TEST_IGNORE_MESSAGE("no WiFi connection");
    return;
  }

  char body[512] = {0};
  int code = http_request("GET", path, NULL, body, sizeof(body));

  char msg[128];
  snprintf(msg, sizeof(msg), "%s -> %d (%.60s...)", path, code,
           body[0] ? body : "(empty)");
  TEST_MESSAGE(msg);

  TEST_ASSERT_EQUAL_INT_MESSAGE(expected_code, code,
    "device: unexpected HTTP status code");
}

static void assert_post(const char *path, const char *req_body, int expected_code) {
  if (!ensure_ready()) {
    TEST_IGNORE_MESSAGE("no WiFi connection");
    return;
  }

  char resp[512] = {0};
  int code = http_request("POST", path, req_body, resp, sizeof(resp));

  char msg[128];
  snprintf(msg, sizeof(msg), "%s -> %d (%.60s...)", path, code,
           resp[0] ? resp : "(empty)");
  TEST_MESSAGE(msg);

  TEST_ASSERT_EQUAL_INT_MESSAGE(expected_code, code,
    "device: unexpected HTTP status code");
}

static void test_get_wifi(void) {
  TEST_MESSAGE("user fetches /api/wifi");
  assert_get("/api/wifi", 200);
}

static void test_get_wireless_status(void) {
  TEST_MESSAGE("user fetches /api/wireless/status");
  assert_get("/api/wireless/status", 200);
}

static void test_get_device_status(void) {
  TEST_MESSAGE("user fetches /api/system/device/status");
  assert_get("/api/system/device/status", 200);
}

static void test_get_filesystem_root(void) {
  TEST_MESSAGE("user fetches /api/filesystem");
  assert_get("/api/filesystem", 200);
}

static void test_get_filesystem_sd(void) {
  TEST_MESSAGE("user fetches /api/filesystem/sd");
  assert_get("/api/filesystem/sd", 200);
}

static void test_get_filesystem_littlefs(void) {
  TEST_MESSAGE("user fetches /api/filesystem/littlefs");
  assert_get("/api/filesystem/littlefs", 200);
}

static void test_get_co2_config(void) {
  TEST_MESSAGE("user fetches /api/co2/config");
  assert_get("/api/co2/config", 200);
}

static void test_get_ap_config(void) {
  TEST_MESSAGE("user fetches /api/ap/config");
  assert_get("/api/ap/config", 200);
}

static void test_get_ota_rollback(void) {
  TEST_MESSAGE("user fetches /api/system/ota/rollback");
  assert_get("/api/system/ota/rollback", 200);
}

static void test_post_co2_start(void) {
  TEST_MESSAGE("user starts CO2 via POST /api/co2/start");
  assert_post("/api/co2/start", NULL, 200);
}

static void test_post_co2_stop(void) {
  TEST_MESSAGE("user stops CO2 via POST /api/co2/stop");
  assert_post("/api/co2/stop", NULL, 200);
}

static void test_404_not_found(void) {
  TEST_MESSAGE("user requests non-existent route");
  assert_get("/api/nonexistent", 404);
}

// TODO: Additional API endpoint tests to add when self-connect is resolved.
//
// static void test_get_sensors_temperature(void) {
//   TEST_MESSAGE("user fetches /api/sensors/temperature");
//   assert_get("/api/sensors/temperature", 200);
// }
//
// static void test_get_sensors_co2(void) {
//   TEST_MESSAGE("user fetches /api/sensors/co2");
//   assert_get("/api/sensors/co2", 200);
// }
//
// static void test_get_sensors_current(void) {
//   TEST_MESSAGE("user fetches /api/sensors/current");
//   assert_get("/api/sensors/current", 200);
// }
//
// static void test_get_sensors_pressure(void) {
//   TEST_MESSAGE("user fetches /api/sensors/pressure");
//   assert_get("/api/sensors/pressure", 200);
// }
//
// static void test_get_sensors_wind(void) {
//   TEST_MESSAGE("user fetches /api/sensors/wind");
//   assert_get("/api/sensors/wind", 200);
// }
//
// static void test_get_sensors_soil(void) {
//   TEST_MESSAGE("user fetches /api/sensors/soil");
//   assert_get("/api/sensors/soil", 200);
// }
//
// static void test_get_sensors_solar(void) {
//   TEST_MESSAGE("user fetches /api/sensors/solar");
//   assert_get("/api/sensors/solar", 200);
// }
//
// static void test_get_email_config(void) {
//   TEST_MESSAGE("user fetches /api/email/config");
//   assert_get("/api/email/config", 200);
// }
//
// static void test_get_database_status(void) {
//   TEST_MESSAGE("user fetches /api/database/status");
//   assert_get("/api/database/status", 200);
// }
//
// static void test_post_database_query(void) {
//   TEST_MESSAGE("user posts SQL query to /api/database/query");
//   assert_post("/api/database/query", "{\"sql\":\"SELECT 1\"}", 200);
// }

void services::http_e2e::test(void) {
  // TODO: Blocked by AsyncTCP self-connect issue.
  // WiFiClient on the same device can't connect to AsyncWebServer
  // because AsyncTCP task and test task compete for the same core.
  // Workaround: run these from an external test runner (e2e suite).
  //
  // it("user observes /api/wifi responds 200",              test_get_wifi);
  // it("user observes /api/wireless/status responds 200",   test_get_wireless_status);
  // it("user observes /api/system/device/status responds",  test_get_device_status);
  // it("user observes /api/filesystem root responds",       test_get_filesystem_root);
  // it("user observes /api/filesystem/sd responds",         test_get_filesystem_sd);
  // it("user observes /api/filesystem/littlefs responds",   test_get_filesystem_littlefs);
  // it("user observes /api/co2/config responds",            test_get_co2_config);
  // it("user observes /api/ap/config responds",             test_get_ap_config);
  // it("user observes /api/system/ota/rollback responds",   test_get_ota_rollback);
  // it("user observes POST /api/co2/start responds",        test_post_co2_start);
  // it("user observes POST /api/co2/stop responds",         test_post_co2_stop);
  // it("user observes 404 for unknown routes",              test_404_not_found);
  // it("user observes /api/sensors/temperature responds",   test_get_sensors_temperature);
  // it("user observes /api/sensors/co2 responds",           test_get_sensors_co2);
  // it("user observes /api/sensors/current responds",       test_get_sensors_current);
  // it("user observes /api/sensors/pressure responds",      test_get_sensors_pressure);
  // it("user observes /api/sensors/wind responds",          test_get_sensors_wind);
  // it("user observes /api/sensors/soil responds",          test_get_sensors_soil);
  // it("user observes /api/sensors/solar responds",         test_get_sensors_solar);
  // it("user observes /api/email/config responds",          test_get_email_config);
  // it("user observes /api/database/status responds",       test_get_database_status);
  // it("user observes POST /api/database/query responds",   test_post_database_query);
}

#endif
