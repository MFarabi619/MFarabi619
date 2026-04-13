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
  file.print("timestamp,epoch,uptime_seconds,temp_humidity_count");
  for (uint8_t index = 0; index < config::temperature_humidity::MAX_SENSORS; index++) {
    file.printf(",temp%u_model,temp%u_temperature_celsius,temp%u_relative_humidity_percent",
                index, index, index);
  }
  file.println(",co2_model,co2_ppm,co2_temperature_celsius,co2_relative_humidity_percent,voltage_0,voltage_1,voltage_2,voltage_3,wind_speed_kilometers_per_hour,wind_direction_degrees,wind_direction_angle_slice");
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

  RTCSnapshot rtc_snapshot = {};
  services::rtc::accessSnapshot(&rtc_snapshot);
  uint32_t epoch = services::rtc::accessEpoch();
  if (networking::sntp::isSynced()) {
    write_field(file, networking::sntp::accessLocalTimeString());
  } else if (rtc_snapshot.valid) {
    write_field(file, rtc_snapshot.iso8601);
  }
  file.print(',');
  if (epoch > 0) file.print(epoch);
  file.print(',');
  file.print(millis() / 1000UL);

  SensorInventorySnapshot inventory = {};
  sensors::manager::accessInventory(&inventory);
  file.print(',');
  file.print(inventory.temperature_humidity_count);

  for (uint8_t index = 0; index < config::temperature_humidity::MAX_SENSORS; index++) {
    TemperatureHumiditySensorData temp_humidity = {};
    bool temp_ok = sensors::manager::accessTemperatureHumidity(index, &temp_humidity);
    file.print(',');
    if (temp_ok) write_field(file, temp_humidity.model);
    file.print(',');
    if (temp_ok) write_float_field(file, temp_humidity.temperature_celsius);
    file.print(',');
    if (temp_ok) write_float_field(file, temp_humidity.relative_humidity_percent);
  }

  CO2SensorData co2 = {};
  bool co2_ok = sensors::manager::accessCO2(&co2);
  file.print(',');
  if (co2_ok) write_field(file, co2.model);
  file.print(',');
  if (co2_ok) write_float_field(file, co2.co2_ppm, 1);
  file.print(',');
  if (co2_ok) write_float_field(file, co2.temperature_celsius);
  file.print(',');
  if (co2_ok) write_float_field(file, co2.relative_humidity_percent);

  VoltageSensorData voltage = {};
  bool voltage_ok = sensors::manager::accessVoltage(&voltage);
  for (size_t channel = 0; channel < config::voltage::CHANNEL_COUNT; channel++) {
    file.print(',');
    if (voltage_ok) write_float_field(file, voltage.channel_volts[channel], 4);
  }

  WindSpeedSensorData wind_speed = {};
  bool wind_speed_ok = sensors::manager::accessWindSpeed(&wind_speed);
  file.print(',');
  if (wind_speed_ok) write_float_field(file, wind_speed.kilometers_per_hour);

  WindDirectionSensorData wind_direction = {};
  bool wind_direction_ok = sensors::manager::accessWindDirection(&wind_direction);
  file.print(',');
  if (wind_direction_ok) write_float_field(file, wind_direction.degrees, 1);
  file.print(',');
  if (wind_direction_ok) file.print(wind_direction.slice);

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
  return true;
}
