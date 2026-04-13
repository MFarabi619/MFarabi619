#include "data_logger.h"

#include "../config.h"
#include "../hardware/storage.h"
#include "../networking/sntp.h"
#include "rtc.h"
#include "../sensors/manager.h"

#include <Arduino.h>
#include <SD.h>

namespace {

bool initialized = false;
bool header_written = false;
uint32_t last_log_ms = 0;

bool ensure_header() {
  if (!hardware::storage::ensureSD()) return false;

  if (SD.exists(config::data_logger::CSV_PATH)) {
    File existing = SD.open(config::data_logger::CSV_PATH, FILE_READ);
    if (existing && existing.size() > 0) {
      existing.close();
      header_written = true;
      return true;
    }
    if (existing) existing.close();
  }

  File file = SD.open(config::data_logger::CSV_PATH, FILE_WRITE);
  if (!file) return false;
  file.print("time");
  for (uint8_t i = 0; i < config::data_logger::TEMP_HUMIDITY_SENSOR_COUNT; i++)
    file.printf(",temperature_celsius_%u", i);
  for (uint8_t i = 0; i < config::data_logger::TEMP_HUMIDITY_SENSOR_COUNT; i++)
    file.printf(",relative_humidity_percent_%u", i);
  for (uint8_t i = 0; i < config::voltage::CHANNEL_COUNT; i++)
    file.printf(",voltage_channel_%u", i);
  file.print(",co2_ppm_0,co2_temperature_celsius_0,co2_relative_humidity_percent_0");
  file.print(",wind_speed_kmh_0,wind_direction_degrees_0");
  file.println();
  file.close();
  header_written = true;
  return true;
}

void write_field(File &file, const char *value) {
  if (value) file.print(value);
}

void write_float_field(File &file, float value, uint8_t decimals = 2) {
  if (!isnan(value)) file.print(value, decimals);
}

void append_row() {
  if (!hardware::storage::ensureSD()) return;

  File file = SD.open(config::data_logger::CSV_PATH, FILE_APPEND);
  if (!file) return;

  constexpr uint8_t n_th = config::data_logger::TEMP_HUMIDITY_SENSOR_COUNT;

  TemperatureHumiditySensorData th[n_th] = {};
  bool th_ok[n_th] = {};
  for (uint8_t i = 0; i < n_th; i++)
    th_ok[i] = sensors::manager::accessTemperatureHumidity(i, &th[i]);

  VoltageSensorData voltage = {};
  bool voltage_ok = sensors::manager::accessVoltage(&voltage);

  CO2SensorData co2 = {};
  bool co2_ok = sensors::manager::accessCO2(&co2);

  WindSpeedSensorData wind_speed = {};
  bool wind_speed_ok = sensors::manager::accessWindSpeed(&wind_speed);

  WindDirectionSensorData wind_direction = {};
  bool wind_direction_ok = sensors::manager::accessWindDirection(&wind_direction);

  if (networking::sntp::isSynced()) {
    write_field(file, networking::sntp::accessLocalTimeString());
  } else {
    RTCSnapshot rtc = {};
    services::rtc::accessSnapshot(&rtc);
    if (rtc.valid) write_field(file, rtc.iso8601);
  }

  for (uint8_t i = 0; i < n_th; i++) {
    file.print(',');
    if (th_ok[i]) write_float_field(file, th[i].temperature_celsius);
  }

  for (uint8_t i = 0; i < n_th; i++) {
    file.print(',');
    if (th_ok[i]) write_float_field(file, th[i].relative_humidity_percent);
  }

  for (uint8_t i = 0; i < config::voltage::CHANNEL_COUNT; i++) {
    file.print(',');
    if (voltage_ok) write_float_field(file, voltage.channel_volts[i], 4);
  }

  file.print(',');
  if (co2_ok) write_float_field(file, co2.co2_ppm, 1);
  file.print(',');
  if (co2_ok) write_float_field(file, co2.temperature_celsius);
  file.print(',');
  if (co2_ok) write_float_field(file, co2.relative_humidity_percent);

  file.print(',');
  if (wind_speed_ok) write_float_field(file, wind_speed.kilometers_per_hour);
  file.print(',');
  if (wind_direction_ok) write_float_field(file, wind_direction.degrees, 1);

  file.println();
  file.close();
}

}

void services::data_logger::initialize() {
  initialized = ensure_header();
  last_log_ms = millis();
}

void services::data_logger::flushNow() {
  if (!initialized) {
    initialized = ensure_header();
    if (!initialized) return;
  }
  last_log_ms = millis();
  append_row();
}

void services::data_logger::service() {
  if (!initialized) {
    initialized = ensure_header();
    if (!initialized) return;
  }
  if (millis() - last_log_ms < config::data_logger::LOG_INTERVAL_MS) return;
  last_log_ms = millis();
  append_row();
}

bool services::data_logger::accessStatus(DataLoggerStatusSnapshot *snapshot) {
  if (!snapshot) return false;
  snapshot->initialized = initialized;
  snapshot->sd_ready = hardware::storage::isSDReady();
  snapshot->header_written = header_written;
  snapshot->interval_ms = config::data_logger::LOG_INTERVAL_MS;
  snapshot->last_log_ms = last_log_ms;
  snapshot->path = config::data_logger::CSV_PATH;
  snapshot->ring_buf_used = 0;
  snapshot->ring_buf_capacity = 0;
  snapshot->ring_buf_overrun = false;
  return true;
}
