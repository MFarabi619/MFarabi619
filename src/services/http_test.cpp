#ifdef PIO_UNIT_TESTING

#include "http.h"
#include "../testing/it.h"

#include <ArduinoJson.h>
#include <LittleFS.h>

// ─────────────────────────────────────────────────────────────────────────────
//  Config
// ─────────────────────────────────────────────────────────────────────────────

static void http_test_port_default(void) {
  TEST_MESSAGE("user verifies HTTP server configuration");
  TEST_ASSERT_EQUAL_INT_MESSAGE(80, CONFIG_HTTP_PORT,
    "device: HTTP port should be 80");
  TEST_MESSAGE("HTTP port is 80");
}

// ─────────────────────────────────────────────────────────────────────────────
//  ArduinoJson: serialization
// ─────────────────────────────────────────────────────────────────────────────

static void json_test_create_and_serialize(void) {
  TEST_MESSAGE("user creates a JSON document and serializes it");

  JsonDocument doc;
  doc["hostname"] = "microvisor";
  doc["port"] = 22;
  doc["active"] = true;

  char buf[128];
  size_t len = serializeJson(doc, buf, sizeof(buf));

  TEST_ASSERT_GREATER_THAN_MESSAGE(0, (int)len,
    "device: serializeJson returned 0");
  TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "\"hostname\":\"microvisor\""),
    "device: hostname not found in serialized JSON");
  TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "\"port\":22"),
    "device: port not found in serialized JSON");
  TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "\"active\":true"),
    "device: active not found in serialized JSON");

  TEST_MESSAGE(buf);
}

static void json_test_measure_length(void) {
  TEST_MESSAGE("user measures JSON length before serializing");

  JsonDocument doc;
  doc["key"] = "value";

  size_t measured = measureJson(doc);
  char buf[64];
  size_t actual = serializeJson(doc, buf, sizeof(buf));

  TEST_ASSERT_EQUAL_UINT32_MESSAGE(measured, actual,
    "device: measureJson doesn't match serializeJson length");

  char msg[48];
  snprintf(msg, sizeof(msg), "measured=%u actual=%u", (unsigned)measured, (unsigned)actual);
  TEST_MESSAGE(msg);
}

// ─────────────────────────────────────────────────────────────────────────────
//  ArduinoJson: deserialization
// ─────────────────────────────────────────────────────────────────────────────

static void json_test_deserialize(void) {
  TEST_MESSAGE("user deserializes a JSON string and reads values");

  const char *input = "{\"sensor\":\"scd4x\",\"co2\":412,\"temp\":23.5,\"ok\":true}";
  JsonDocument doc;
  DeserializationError error = deserializeJson(doc, input);

  TEST_ASSERT_FALSE_MESSAGE((bool)error,
    "device: deserialization failed");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("scd4x", doc["sensor"].as<const char *>(),
    "device: sensor value mismatch");
  TEST_ASSERT_EQUAL_INT_MESSAGE(412, doc["co2"].as<int>(),
    "device: co2 value mismatch");
  TEST_ASSERT_FLOAT_WITHIN_MESSAGE(0.01f, 23.5f, doc["temp"].as<float>(),
    "device: temp value mismatch");
  TEST_ASSERT_TRUE_MESSAGE(doc["ok"].as<bool>(),
    "device: ok should be true");

  TEST_MESSAGE("deserialization verified");
}

static void json_test_default_values(void) {
  TEST_MESSAGE("user reads missing keys with defaults using | operator");

  JsonDocument doc;
  deserializeJson(doc, "{\"port\":8080}");

  int port = doc["port"] | 3000;
  int missing = doc["timeout"] | 5000;

  TEST_ASSERT_EQUAL_INT_MESSAGE(8080, port,
    "device: existing key should return its value");
  TEST_ASSERT_EQUAL_INT_MESSAGE(5000, missing,
    "device: missing key should return default");

  TEST_MESSAGE("default value operator | verified");
}

// ─────────────────────────────────────────────────────────────────────────────
//  ArduinoJson: nested structures
// ─────────────────────────────────────────────────────────────────────────────

static void json_test_nested_objects_and_arrays(void) {
  TEST_MESSAGE("user creates nested objects and arrays");

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

static void json_test_file_roundtrip(void) {
  TEST_MESSAGE("user writes JSON to LittleFS and reads it back");

  LittleFS.begin(true);
  const char *path = "/.test_json.tmp";

  // Write
  JsonDocument write_doc;
  write_doc["hostname"] = "microvisor";
  write_doc["port"] = 22;

  File writer = LittleFS.open(path, FILE_WRITE);
  TEST_ASSERT_TRUE_MESSAGE((bool)writer, "device: open for write failed");
  serializeJson(write_doc, writer);
  writer.close();

  // Read
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
  TEST_MESSAGE("JSON file roundtrip verified");
}

void http_run_tests(void) {
  it("user observes that HTTP port is configured to 80",
     http_test_port_default);
  it("user observes that ArduinoJson creates and serializes a document",
     json_test_create_and_serialize);
  it("user observes that measureJson matches actual serialized length",
     json_test_measure_length);
  it("user observes that ArduinoJson deserializes and reads values correctly",
     json_test_deserialize);
  it("user observes that missing keys return defaults via | operator",
     json_test_default_values);
  it("user observes that nested objects and arrays work",
     json_test_nested_objects_and_arrays);
  it("user observes that JSON roundtrips through LittleFS",
     json_test_file_roundtrip);
}

#endif
