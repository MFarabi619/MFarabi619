#include "cloudevents.h"
#include "../config.h"
#include "../drivers/ads1115.h"
#include "temperature_and_humidity.h"

#include <Arduino.h>
#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include <ArduinoJson.h>

#include <time.h>

// ─────────────────────────────────────────────────────────────────────────────
//  CloudEvents configuration
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_SENSOR_TEMPERATURE_HUMIDITY_ENABLED
#define CONFIG_SENSOR_TEMPERATURE_HUMIDITY_ENABLED 1
#endif

#ifndef CONFIG_SENSOR_VOLTAGE_MONITOR_ENABLED
#define CONFIG_SENSOR_VOLTAGE_MONITOR_ENABLED 1
#endif

static const char *MIME_CLOUDEVENTS_BATCH = "application/cloudevents-batch+json";
static const char *SPECVERSION = "1.0";

// ─────────────────────────────────────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────────────────────────────────────

static String cloudevents_source(void) {
  return String("urn:apidae-systems:tenant:") + CONFIG_CLOUDEVENTS_TENANT +
         ":site:" + CONFIG_CLOUDEVENTS_SITE;
}

static String cloudevents_event_id(const char *type_name, uint16_t sequence) {
  return String(type_name) + "-" +
         String(static_cast<unsigned long>(millis())) + "-" +
         String(sequence);
}

static String cloudevents_now_iso8601(void) {
  const time_t now = time(nullptr);
  if (now <= 0) return "";

  struct tm utc_time;
  gmtime_r(&now, &utc_time);
  char buffer[32] = {0};
  strftime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%SZ", &utc_time);
  return String(buffer);
}

static JsonObject cloudevents_add_event(JsonArray events, uint16_t sequence,
                                        const String &source,
                                        const char *type_name,
                                        const String &time_iso) {
  JsonObject event = events.add<JsonObject>();
  event["specversion"] = SPECVERSION;
  event["id"] = cloudevents_event_id(type_name, sequence);
  event["source"] = source;
  event["type"] = type_name;
  event["datacontenttype"] = "application/json";
  if (time_iso.length() > 0) {
    event["time"] = time_iso;
  }
  return event;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Event appenders
// ─────────────────────────────────────────────────────────────────────────────

static void append_status_event(JsonArray events, uint16_t sequence,
                                const String &source, const String &time_iso) {
  JsonObject event = cloudevents_add_event(events, sequence, source,
                                           "status.v1", time_iso);
  JsonObject data = event["data"].to<JsonObject>();
  data["memory_heap"] = ESP.getFreeHeap();
  data["chip_model"] = ESP.getChipModel();
  data["chip_cores"] = ESP.getChipCores();
  data["chip_revision"] = ESP.getChipRevision();
  data["ipv4_address"] = WiFi.localIP().toString();
  data["wifi_rssi"] = WiFi.RSSI();
  data["uptime_seconds"] = millis() / 1000UL;
}

#if CONFIG_SENSOR_TEMPERATURE_HUMIDITY_ENABLED == 1
static void append_temperature_humidity_event(JsonArray events,
                                              uint16_t sequence,
                                              const String &source,
                                              const String &time_iso) {
  JsonObject event = cloudevents_add_event(events, sequence, source,
      "sensors.temperature_and_humidity.v1", time_iso);
  JsonObject data = event["data"].to<JsonObject>();

  uint8_t count = temperature_and_humidity_sensor_count();
  JsonArray sensors = data["sensors"].to<JsonArray>();
  uint16_t successful_reads = 0;

  for (uint8_t index = 0; index < count; index++) {
    JsonObject sensor = sensors.add<JsonObject>();
    sensor["index"] = index;

    float temperature_celsius = 0.0f;
    float relative_humidity_percent = 0.0f;
    bool read_ok = temperature_and_humidity_read(index,
        &temperature_celsius, &relative_humidity_percent);

    sensor["read_ok"] = read_ok;
    if (read_ok) {
      sensor["temperature_celsius"] = temperature_celsius;
      sensor["relative_humidity_percent"] = relative_humidity_percent;
      successful_reads++;
    }
  }

  data["sensor_count"] = count;
  data["successful_reads"] = successful_reads;
  data["read_ok"] = successful_reads > 0;
}
#endif

#if CONFIG_SENSOR_VOLTAGE_MONITOR_ENABLED == 1
static void append_voltage_event(JsonArray events, uint16_t sequence,
                                 const String &source,
                                 const String &time_iso) {
  JsonObject event = cloudevents_add_event(events, sequence, source,
                                           "sensors.power.v1", time_iso);
  JsonObject data = event["data"].to<JsonObject>();

  float channel_volts[CONFIG_VOLTAGE_MONITOR_CHANNEL_COUNT];
  bool read_ok = ads1115_read(channel_volts, CONFIG_VOLTAGE_MONITOR_CHANNEL_COUNT);

  data["read_ok"] = read_ok;
  data["gain"] = ads1115_gain_label();

  if (read_ok) {
    JsonArray voltage = data["voltage"].to<JsonArray>();
    for (size_t channel = 0; channel < CONFIG_VOLTAGE_MONITOR_CHANNEL_COUNT;
         channel++) {
      voltage.add(channel_volts[channel]);
    }
  }
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  Route handler
// ─────────────────────────────────────────────────────────────────────────────

static void handle_cloudevents_get(AsyncWebServerRequest *request) {
  JsonDocument payload;
  JsonArray events = payload.to<JsonArray>();

  const String source = cloudevents_source();
  const String time_iso = cloudevents_now_iso8601();

  uint16_t sequence = 0;
  append_status_event(events, sequence++, source, time_iso);

#if CONFIG_SENSOR_TEMPERATURE_HUMIDITY_ENABLED == 1
  append_temperature_humidity_event(events, sequence++, source, time_iso);
#endif

#if CONFIG_SENSOR_VOLTAGE_MONITOR_ENABLED == 1
  append_voltage_event(events, sequence++, source, time_iso);
#endif

  AsyncResponseStream *response =
      request->beginResponseStream(MIME_CLOUDEVENTS_BATCH);
  serializeJson(payload, *response);
  request->send(response);
}

void cloudevents_register_routes(AsyncWebServer *server) {
  if (!server) return;
  server->on("/api/cloudevents", HTTP_GET, handle_cloudevents_get);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tests — describe("CloudEvents")
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING

#include "../testing/it.h"

static void cloudevents_test_source_format(void) {
  TEST_MESSAGE("user verifies CloudEvents source string format");

  String source = cloudevents_source();
  TEST_ASSERT_EQUAL_STRING_MESSAGE(
      "urn:apidae-systems:tenant:" CONFIG_CLOUDEVENTS_TENANT
      ":site:" CONFIG_CLOUDEVENTS_SITE,
      source.c_str(),
      "device: source string should use tenant and site config");

  TEST_MESSAGE(source.c_str());
}

static void cloudevents_test_event_id_includes_type(void) {
  TEST_MESSAGE("user verifies event ID includes type prefix");

  String event_id = cloudevents_event_id("status.v1", 0);
  TEST_ASSERT_TRUE_MESSAGE(event_id.startsWith("status.v1-"),
      "device: event ID should start with type name");

  TEST_MESSAGE(event_id.c_str());
}

void cloudevents_run_tests(void) {
  it("user verifies CloudEvents source string format",
     cloudevents_test_source_format);
  it("user verifies event ID includes type prefix",
     cloudevents_test_event_id_includes_type);
}

#endif
