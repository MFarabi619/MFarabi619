#include "cloudevents.h"
#include "../config.h"
#include "system.h"
#include "../sensors/manager.h"

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
  return String("urn:apidae-systems:tenant:") + config::cloudevents::TENANT +
         ":site:" + config::cloudevents::SITE;
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
  SystemQuery query = {
    .preferred_storage = StorageKind::LittleFS,
    .snapshot = {},
  };
  services::system::accessSnapshot(&query);
  data["memory_heap"] = query.snapshot.heap_free;
  data["chip_model"] = query.snapshot.chip_model;
  data["chip_cores"] = query.snapshot.chip_cores;
  data["chip_revision"] = query.snapshot.chip_revision;
  data["ipv4_address"] = query.snapshot.network.ip;
  data["wifi_rssi"] = query.snapshot.network.rssi;
  data["uptime_seconds"] = millis() / 1000UL;
}

#if CONFIG_SENSOR_TEMPERATURE_HUMIDITY_ENABLED == 1
static void append_temperature_humidity_event(JsonArray events,
                                              uint16_t sequence,
                                              const String &source,
                                              const String &time_iso) {
  SensorInventorySnapshot inventory = {};
  sensors::manager::accessInventory(&inventory);
  uint8_t count = inventory.temperature_humidity_count;
  if (count == 0) return;

  JsonObject event = cloudevents_add_event(events, sequence, source,
      "sensors.temperature_and_humidity.v1", time_iso);
  JsonObject data = event["data"].to<JsonObject>();

  JsonArray sensor_entries = data["sensors"].to<JsonArray>();
  uint16_t successful_reads = 0;

  for (uint8_t index = 0; index < count; index++) {
    JsonObject sensor = sensor_entries.add<JsonObject>();
    sensor["index"] = index;

    TemperatureHumiditySensorData sensor_data = {};
    bool read_ok = sensors::manager::accessTemperatureHumidity(index, &sensor_data);

    sensor["read_ok"] = read_ok;
    if (read_ok) {
      sensor["model"] = sensor_data.model ? sensor_data.model : "unknown";
      sensor["temperature_celsius"] = sensor_data.temperature_celsius;
      sensor["relative_humidity_percent"] = sensor_data.relative_humidity_percent;
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

  VoltageSensorData sensor_data = {};
  bool read_ok = sensors::manager::accessVoltage(&sensor_data);
  
  data["read_ok"] = read_ok;
  data["gain"] = sensors::voltage::accessGainLabel();

  if (read_ok) {
    JsonArray voltage = data["voltage"].to<JsonArray>();
    for (size_t channel = 0; channel < config::voltage::CHANNEL_COUNT;
         channel++) {
      voltage.add(sensor_data.channel_volts[channel]);
    }
  }
}
#endif

static void append_co2_event(JsonArray events, uint16_t sequence,
                             const String &source, const String &time_iso) {
  CO2SensorData sensor_data = {};
  if (!sensors::manager::accessCO2(&sensor_data) || !sensor_data.ok) return;

  JsonObject event = cloudevents_add_event(events, sequence, source,
                                           "sensors.carbon_dioxide.v1", time_iso);
  JsonObject data = event["data"].to<JsonObject>();
  data["model"] = sensor_data.model;
  data["co2_ppm"] = sensor_data.co2_ppm;
  data["temperature"] = sensor_data.temperature_celsius;
  data["humidity"] = sensor_data.relative_humidity_percent;
}

static void append_wind_speed_event(JsonArray events, uint16_t sequence,
                                    const String &source, const String &time_iso) {
  WindSpeedSensorData sensor_data = {};
  if (!sensors::manager::accessWindSpeed(&sensor_data) || !sensor_data.ok) return;

  JsonObject event = cloudevents_add_event(events, sequence, source,
                                           "sensors.wind_speed.v1", time_iso);
  JsonObject data = event["data"].to<JsonObject>();
  data["wind_speed_kilometers_per_hour"] = sensor_data.kilometers_per_hour;
}

static void append_wind_direction_event(JsonArray events, uint16_t sequence,
                                        const String &source, const String &time_iso) {
  WindDirectionSensorData sensor_data = {};
  if (!sensors::manager::accessWindDirection(&sensor_data) || !sensor_data.ok) return;

  JsonObject event = cloudevents_add_event(events, sequence, source,
                                           "sensors.wind_direction.v1", time_iso);
  JsonObject data = event["data"].to<JsonObject>();
  data["wind_direction_degrees"] = sensor_data.degrees;
  data["wind_direction_angle_slice"] = sensor_data.slice;
}

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

  append_co2_event(events, sequence++, source, time_iso);
  append_wind_speed_event(events, sequence++, source, time_iso);
  append_wind_direction_event(events, sequence++, source, time_iso);

  AsyncResponseStream *response =
      request->beginResponseStream(MIME_CLOUDEVENTS_BATCH);
  serializeJson(payload, *response);
  request->send(response);
}

void services::cloudevents::registerRoutes(AsyncWebServer *server) {
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
  String expected = String("urn:apidae-systems:tenant:") +
                     config::cloudevents::TENANT + ":site:" +
                     config::cloudevents::SITE;
  TEST_ASSERT_EQUAL_STRING_MESSAGE(
      expected.c_str(),
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

void services::cloudevents::test(void) {
  it("user verifies CloudEvents source string format",
     cloudevents_test_source_format);
  it("user verifies event ID includes type prefix",
     cloudevents_test_event_id_includes_type);
}

#endif
