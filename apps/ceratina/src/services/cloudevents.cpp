#include "cloudevents.h"
#include <config.h>
#include <services/system.h>
#include "../sensors/registry.h"
#include <manager.h>

#include <Arduino.h>
#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include <ArduinoJson.h>

#include <time.h>

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
  event["datacontenttype"] = asyncsrv::T_application_json;
  if (time_iso.length() > 0) {
    event["time"] = time_iso;
  }
  return event;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Status event (system info, not a sensor)
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

// ─────────────────────────────────────────────────────────────────────────────
//  Sensor serializers (SensorKind → JSON fields)
// ─────────────────────────────────────────────────────────────────────────────

static void serialize_temperature_humidity(const void *raw, JsonObject &out) {
  auto *d = static_cast<const TemperatureHumiditySensorData *>(raw);
  out["model"] = d->model ? d->model : "unknown";
  out["temperature_celsius"] = d->temperature_celsius;
  out["relative_humidity_percent"] = d->relative_humidity_percent;
}

static void serialize_voltage(const void *raw, JsonObject &out) {
  auto *d = static_cast<const VoltageSensorData *>(raw);
  out["gain"] = sensors::voltage::accessGainLabel();
  JsonArray voltage = out["voltage"].to<JsonArray>();
  for (size_t ch = 0; ch < config::voltage::CHANNEL_COUNT; ch++)
    voltage.add(d->channel_volts[ch]);
  JsonArray temperature = out["temperature_celsius"].to<JsonArray>();
  for (size_t ch = 0; ch < config::voltage::CHANNEL_COUNT; ch++)
    temperature.add(d->temperature_celsius[ch]);
}

static void serialize_current(const void *raw, JsonObject &out) {
  auto *d = static_cast<const CurrentSensorData *>(raw);
  out["current_mA"] = d->current_mA;
  out["bus_voltage_V"] = d->bus_voltage_V;
  out["shunt_voltage_mV"] = d->shunt_voltage_mV;
  out["power_mW"] = d->power_mW;
  out["energy_J"] = d->energy_J;
  out["charge_C"] = d->charge_C;
  out["die_temperature_C"] = d->die_temperature_C;
}

static void serialize_co2(const void *raw, JsonObject &out) {
  auto *d = static_cast<const CO2SensorData *>(raw);
  out["model"] = d->model;
  out["co2_ppm"] = d->co2_ppm;
  out["temperature"] = d->temperature_celsius;
  out["humidity"] = d->relative_humidity_percent;
}

static void serialize_barometric_pressure(const void *raw, JsonObject &out) {
  auto *d = static_cast<const BarometricPressureSensorData *>(raw);
  out["model"] = d->model;
  out["pressure_hpa"] = d->pressure_hpa;
  out["temperature_celsius"] = d->temperature_celsius;
}

static void serialize_wind_speed(const void *raw, JsonObject &out) {
  auto *d = static_cast<const WindSpeedSensorData *>(raw);
  out["wind_speed_kilometers_per_hour"] = d->kilometers_per_hour;
}

static void serialize_wind_direction(const void *raw, JsonObject &out) {
  auto *d = static_cast<const WindDirectionSensorData *>(raw);
  out["wind_direction_degrees"] = d->degrees;
  out["wind_direction_angle_slice"] = d->slice;
}

static void serialize_solar_radiation(const void *raw, JsonObject &out) {
  auto *d = static_cast<const SolarRadiationSensorData *>(raw);
  out["watts_per_square_meter"] = d->watts_per_square_meter;
}

static void serialize_soil(const void *raw, JsonObject &out) {
  auto *d = static_cast<const SoilSensorData *>(raw);
  out["slave_id"] = d->slave_id;
  out["temperature_celsius"] = d->temperature_celsius;
  out["moisture_percent"] = d->moisture_percent;
  out["conductivity"] = d->conductivity;
  out["salinity"] = d->salinity;
  out["tds"] = d->tds;
  out["has_ph"] = d->has_ph;
  if (d->has_ph) out["ph"] = d->ph;
}

struct SensorSerializer {
  SensorKind kind;
  const char *event_type;
  void (*serialize)(const void *data, JsonObject &out);
};

static void serialize_rainfall(const void *raw, JsonObject &out) {
  auto *d = static_cast<const RainfallSensorData *>(raw);
  out["rainfall_millimeters"] = d->millimeters;
}

static const SensorSerializer SERIALIZERS[] = {
  {SensorKind::TemperatureHumidity, "sensors.temperature_and_humidity.v1", serialize_temperature_humidity},
  {SensorKind::Voltage,             "sensors.power.v1",                   serialize_voltage},
  {SensorKind::Current,             "sensors.current.v1",                 serialize_current},
  {SensorKind::CarbonDioxide,       "sensors.carbon_dioxide.v1",          serialize_co2},
  {SensorKind::BarometricPressure,   "sensors.barometric_pressure.v1",    serialize_barometric_pressure},
  {SensorKind::WindSpeed,           "sensors.wind_speed.v1",              serialize_wind_speed},
  {SensorKind::WindDirection,       "sensors.wind_direction.v1",          serialize_wind_direction},
  {SensorKind::SolarRadiation,      "sensors.solar_radiation.v1",         serialize_solar_radiation},
  {SensorKind::Soil,                "sensors.soil.v1",                    serialize_soil},
  {SensorKind::Rain,                "sensors.rainfall.v1",                serialize_rainfall},
};

static const SensorSerializer *find_serializer(SensorKind kind) {
  for (const auto &s : SERIALIZERS) {
    if (s.kind == kind) return &s;
  }
  return nullptr;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Registry-driven sensor event appender
// ─────────────────────────────────────────────────────────────────────────────

static void append_sensor_events(JsonArray events, uint16_t &sequence,
                                 const String &source, const String &time_iso) {
  for (uint8_t i = 0; i < sensors::registry::entryCount(); i++) {
    const SensorEntry *entry = sensors::registry::entry(i);
    if (!entry || !entry->isAvailable()) continue;

    const SensorSerializer *ser = find_serializer(entry->kind);
    if (!ser) continue;

    uint8_t count = entry->instanceCount();
    if (count == 0) continue;

    JsonObject event = cloudevents_add_event(events, sequence++, source,
                                             ser->event_type, time_iso);
    JsonObject data = event["data"].to<JsonObject>();

    if (count == 1) {
      const void *snapshot = sensors::registry::latest(entry->kind, 0);
      bool ok = sensors::registry::valid(entry->kind, 0);
      data["read_ok"] = ok;
      if (ok && snapshot) {
        ser->serialize(snapshot, data);
      }
    } else {
      data["sensor_count"] = count;
      JsonArray instances = data["sensors"].to<JsonArray>();
      uint16_t successful = 0;
      for (uint8_t j = 0; j < count; j++) {
        const void *snapshot = sensors::registry::latest(entry->kind, j);
        bool ok = sensors::registry::valid(entry->kind, j);
        JsonObject inst = instances.add<JsonObject>();
        inst["index"] = j;
        inst["read_ok"] = ok;
        if (ok && snapshot) {
          ser->serialize(snapshot, inst);
          successful++;
        }
      }
      data["successful_reads"] = successful;
    }
  }
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
  append_sensor_events(events, sequence, source, time_iso);

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

#include <testing/utils.h>

static void test_cloudevents_source_format(void) {
  WHEN("the CloudEvents source string is generated");
  THEN("it contains tenant and site config");

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

static void test_cloudevents_event_id_includes_type(void) {
  WHEN("an event ID is generated");
  THEN("it starts with the type prefix");

  String event_id = cloudevents_event_id("status.v1", 0);
  TEST_ASSERT_TRUE_MESSAGE(event_id.startsWith("status.v1-"),
      "device: event ID should start with type name");

  TEST_MESSAGE(event_id.c_str());
}

void services::cloudevents::test(void) {
  MODULE("CloudEvents");
  RUN_TEST(test_cloudevents_source_format);
  RUN_TEST(test_cloudevents_event_id_includes_type);
}

#endif
