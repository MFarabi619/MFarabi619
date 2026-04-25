#include "data_logger.h"

#include <config.h>
#include <storage.h>
#include "../networking/sntp.h"
#include "../sensors/temperature_and_humidity.h"
#include "../sensors/voltage.h"
#include "../sensors/carbon_dioxide.h"
#include "../sensors/barometric_pressure.h"
#include "../sensors/wind_speed.h"
#include "../sensors/wind_direction.h"
#include "rtc.h"
#include <manager.h>

#include <Arduino.h>
#include <SD.h>
#include <freertos/timers.h>

namespace {

bool initialized = false;
bool header_written = false;
uint32_t last_log_ms = 0;

void write_timestamp(File &file) {
  if (networking::sntp::isSynced()) {
    const char *ts = networking::sntp::accessLocalTimeString();
    if (ts) file.print(ts);
  } else {
    RTCSnapshot rtc = {};
    services::rtc::accessSnapshot(&rtc);
    if (rtc.valid) file.print(rtc.iso8601);
  }
}

void write_float(File &file, float value, uint8_t decimals = 2) {
  if (!isnan(value)) file.print(value, decimals);
}

bool ensure_csv(const char *path, const char *header) {
  if (SD.exists(path)) {
    File existing = SD.open(path, FILE_READ);
    if (existing && existing.size() > 0) {
      existing.close();
      return true;
    }
    if (existing) existing.close();
  }
  File file = SD.open(path, FILE_WRITE);
  if (!file) return false;
  file.println(header);
  file.close();
  return true;
}

bool ensure_headers() {
  if (!hardware::storage::ensureSD()) return false;

  uint8_t n_th = sensors::temperature_and_humidity::sensorCount();
  if (n_th > 0) {
    char header[256] = {0};
    size_t pos = 0;
    for (uint8_t i = 0; i < n_th; i++) {
      if (i > 0) header[pos++] = ',';
      pos += snprintf(header + pos, sizeof(header) - pos,
                      "temperature_celsius_%u,relative_humidity_percent_%u", i, i);
    }
    pos += snprintf(header + pos, sizeof(header) - pos, ",time");
    ensure_csv("/temperature_humidity.csv", header);
  }

  if (sensors::voltage::isAvailable())
    ensure_csv("/voltage.csv",
               "channel_0,temperature_celsius_0,"
               "channel_1,temperature_celsius_1,"
               "channel_2,temperature_celsius_2,"
               "channel_3,temperature_celsius_3,time");

  if (sensors::carbon_dioxide::isAvailable())
    ensure_csv("/co2.csv", "co2_ppm,temperature_celsius,relative_humidity_percent,time");

  if (sensors::barometric_pressure::isAvailable())
    ensure_csv("/pressure.csv", "pressure_hpa,temperature_celsius,time");

  if (sensors::wind_speed::isAvailable() || sensors::wind_direction::isAvailable())
    ensure_csv("/wind.csv", "wind_speed_kmh,wind_direction_degrees,time");

  header_written = true;
  return true;
}

void log_temperature_humidity() {
  uint8_t n_th = sensors::temperature_and_humidity::sensorCount();
  if (n_th == 0) return;

  File file = SD.open("/temperature_humidity.csv", FILE_APPEND);
  if (!file) return;

  for (uint8_t i = 0; i < n_th; i++) {
    TemperatureHumiditySensorData th = {};
    bool ok = sensors::manager::accessTemperatureHumidity(i, &th);
    if (i > 0) file.print(',');
    if (ok) write_float(file, th.temperature_celsius);
    file.print(',');
    if (ok) write_float(file, th.relative_humidity_percent);
  }
  file.print(',');
  write_timestamp(file);
  file.println();
  file.close();
}

void log_voltage() {
  VoltageSensorData voltage = {};
  if (!sensors::manager::accessVoltage(&voltage)) return;

  File file = SD.open("/voltage.csv", FILE_APPEND);
  if (!file) return;

  for (size_t i = 0; i < config::voltage::CHANNEL_COUNT; i++) {
    if (i > 0) file.print(',');
    write_float(file, voltage.channel_volts[i], 4);
    file.print(',');
    write_float(file, voltage.temperature_celsius[i], 2);
  }
  file.print(',');
  write_timestamp(file);
  file.println();
  file.close();
}

void log_co2() {
  CO2SensorData co2 = {};
  if (!sensors::manager::accessCO2(&co2)) return;

  File file = SD.open("/co2.csv", FILE_APPEND);
  if (!file) return;

  write_float(file, co2.co2_ppm, 1);
  file.print(','); write_float(file, co2.temperature_celsius);
  file.print(','); write_float(file, co2.relative_humidity_percent);
  file.print(','); write_timestamp(file);
  file.println();
  file.close();
}

void log_pressure() {
  BarometricPressureSensorData pressure = {};
  if (!sensors::manager::accessBarometricPressure(&pressure)) return;

  File file = SD.open("/pressure.csv", FILE_APPEND);
  if (!file) return;

  write_float(file, pressure.pressure_hpa);
  file.print(','); write_float(file, pressure.temperature_celsius);
  file.print(','); write_timestamp(file);
  file.println();
  file.close();
}

void log_wind() {
  WindSpeedSensorData wind_speed = {};
  WindDirectionSensorData wind_direction = {};
  bool has_speed = sensors::manager::accessWindSpeed(&wind_speed);
  bool has_dir = sensors::manager::accessWindDirection(&wind_direction);
  if (!has_speed && !has_dir) return;

  File file = SD.open("/wind.csv", FILE_APPEND);
  if (!file) return;

  if (has_speed) write_float(file, wind_speed.kilometers_per_hour);
  file.print(',');
  if (has_dir) write_float(file, wind_direction.degrees, 1);
  file.print(',');
  write_timestamp(file);
  file.println();
  file.close();
}

void append_all() {
  if (!hardware::storage::ensureSD()) return;
  log_temperature_humidity();
  log_voltage();
  log_co2();
  log_pressure();
  log_wind();
}

}

namespace {

TimerHandle_t log_timer = nullptr;

void log_timer_callback(TimerHandle_t) {
  if (!initialized) {
    initialized = ensure_headers();
    if (!initialized) return;
  }
  append_all();
}

}

void services::data_logger::initialize() {
  initialized = ensure_headers();

  log_timer = xTimerCreate("data-log", pdMS_TO_TICKS(config::data_logger::LOG_INTERVAL_MS),
                            pdTRUE, nullptr, log_timer_callback);
  xTimerStart(log_timer, 0);
}

void services::data_logger::flushNow() {
  if (!initialized) {
    initialized = ensure_headers();
    if (!initialized) return;
  }
  append_all();
}

bool services::data_logger::accessStatus(DataLoggerStatusSnapshot *snapshot) {
  if (!snapshot) return false;
  snapshot->initialized = initialized;
  snapshot->sd_ready = hardware::storage::isSDReady();
  snapshot->header_written = header_written;
  snapshot->interval_ms = config::data_logger::LOG_INTERVAL_MS;
  snapshot->last_log_ms = last_log_ms;
  snapshot->path = "/temperature_humidity.csv";
  snapshot->ring_buf_used = 0;
  snapshot->ring_buf_capacity = 0;
  snapshot->ring_buf_overrun = false;
  return true;
}

#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>
#include <SD.h>

namespace services::data_logger { void test(void); }

static void check_csv_header(const char *path, const char *expected_prefix) {
  File check = SD.open(path, FILE_READ);
  if (!check) {
    char msg[64];
    snprintf(msg, sizeof(msg), "skipped — %s not created (no sensor)", path);
    TEST_IGNORE_MESSAGE(msg);
    return;
  }
  char buf[256] = {};
  size_t len = check.readBytesUntil('\n', buf, sizeof(buf) - 1);
  check.close();

  char msg[128];
  snprintf(msg, sizeof(msg), "%s: %s", path, buf);
  TEST_MESSAGE(msg);

  TEST_ASSERT_GREATER_THAN_MESSAGE(0, (int)len, "device: header is empty");
  TEST_ASSERT_TRUE_MESSAGE(strncmp(buf, expected_prefix, strlen(expected_prefix)) == 0,
    "device: header must start with expected prefix");
}

static void test_csv_headers_created(void) {
  GIVEN("SD card is available");
  WHEN("ensure_headers() creates per-sensor CSV files");
  THEN("each file has a valid header with the expected prefix");
  if (!hardware::storage::ensureSD()) {
    TEST_IGNORE_MESSAGE("skipped — no SD card");
    return;
  }

  check_csv_header("/co2.csv", "co2_ppm,");
  check_csv_header("/voltage.csv", "channel_0,");
  check_csv_header("/pressure.csv", "pressure_hpa,");
  check_csv_header("/wind.csv", "wind_speed_kmh,");
  check_csv_header("/temperature_humidity.csv", "temperature_celsius_0,");
}

void services::data_logger::test(void) {
  MODULE("CSV");
  RUN_TEST(test_csv_headers_created);
}

#endif
