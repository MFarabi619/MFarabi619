#include "manager.h"
#include "registry.h"

#include <i2c.h>
#include "../networking/modbus.h"

#include <Arduino.h>
#include <freertos/timers.h>

namespace {

constexpr uint32_t SENSOR_POLL_MS = 5000;
TimerHandle_t poll_timer = nullptr;

void poll_timer_callback(TimerHandle_t) {
  sensors::registry::pollAll();
}

}

void sensors::manager::initialize() {
  hardware::i2c::runDiscovery();

  sensors::temperature_and_humidity::initialize();
  sensors::voltage::initialize();
  sensors::current::initialize();
  sensors::carbon_dioxide::initialize();
  networking::modbus::initialize();
  sensors::wind_speed::initialize();
  if (sensors::wind_speed::isAvailable()) delay(config::wind::SENSOR_DELAY_MS);
  sensors::wind_direction::initialize();
  sensors::solar_radiation::initialize();
  sensors::barometric_pressure::initialize();
  sensors::soil::initialize();

  sensors::registry::pollAll();

  poll_timer = xTimerCreate("sensor-poll", pdMS_TO_TICKS(SENSOR_POLL_MS),
                            pdTRUE, nullptr, poll_timer_callback);
  xTimerStart(poll_timer, 0);
}

bool sensors::manager::accessInventory(SensorInventorySnapshot *snapshot) {
  if (!snapshot) return false;
  snapshot->temperature_humidity_count =
      sensors::registry::instanceCount(SensorKind::TemperatureHumidity);
  snapshot->soil_probe_count =
      sensors::registry::instanceCount(SensorKind::Soil);
  snapshot->voltage_available =
      sensors::registry::isAvailable(SensorKind::Voltage);
  snapshot->current_available =
      sensors::registry::isAvailable(SensorKind::Current);
  snapshot->carbon_dioxide_available =
      sensors::registry::isAvailable(SensorKind::CarbonDioxide);
  snapshot->wind_speed_available =
      sensors::registry::isAvailable(SensorKind::WindSpeed);
  snapshot->wind_direction_available =
      sensors::registry::isAvailable(SensorKind::WindDirection);
  snapshot->solar_radiation_available =
      sensors::registry::isAvailable(SensorKind::SolarRadiation);
  snapshot->barometric_pressure_available =
      sensors::registry::isAvailable(SensorKind::BarometricPressure);
  return true;
}

bool sensors::manager::accessCO2(CO2SensorData *out) {
  if (!out) return false;
  auto *src = static_cast<const CO2SensorData *>(
      sensors::registry::latest(SensorKind::CarbonDioxide));
  if (!src) return false;
  *out = *src;
  return sensors::registry::valid(SensorKind::CarbonDioxide);
}

bool sensors::manager::accessVoltage(VoltageSensorData *out) {
  if (!out) return false;
  auto *src = static_cast<const VoltageSensorData *>(
      sensors::registry::latest(SensorKind::Voltage));
  if (!src) return false;
  *out = *src;
  return sensors::registry::valid(SensorKind::Voltage);
}

bool sensors::manager::accessCurrent(CurrentSensorData *out) {
  if (!out) return false;
  auto *src = static_cast<const CurrentSensorData *>(
      sensors::registry::latest(SensorKind::Current));
  if (!src) return false;
  *out = *src;
  return sensors::registry::valid(SensorKind::Current);
}

bool sensors::manager::accessWindSpeed(WindSpeedSensorData *out) {
  if (!out) return false;
  auto *src = static_cast<const WindSpeedSensorData *>(
      sensors::registry::latest(SensorKind::WindSpeed));
  if (!src) return false;
  *out = *src;
  return sensors::registry::valid(SensorKind::WindSpeed);
}

bool sensors::manager::accessWindDirection(WindDirectionSensorData *out) {
  if (!out) return false;
  auto *src = static_cast<const WindDirectionSensorData *>(
      sensors::registry::latest(SensorKind::WindDirection));
  if (!src) return false;
  *out = *src;
  return sensors::registry::valid(SensorKind::WindDirection);
}

bool sensors::manager::accessSolarRadiation(SolarRadiationSensorData *out) {
  if (!out) return false;
  auto *src = static_cast<const SolarRadiationSensorData *>(
      sensors::registry::latest(SensorKind::SolarRadiation));
  if (!src) return false;
  *out = *src;
  return sensors::registry::valid(SensorKind::SolarRadiation);
}

bool sensors::manager::accessBarometricPressure(BarometricPressureSensorData *out) {
  if (!out) return false;
  auto *src = static_cast<const BarometricPressureSensorData *>(
      sensors::registry::latest(SensorKind::BarometricPressure));
  if (!src) return false;
  *out = *src;
  return sensors::registry::valid(SensorKind::BarometricPressure);
}

bool sensors::manager::accessTemperatureHumidity(uint8_t index,
                                                  TemperatureHumiditySensorData *out) {
  if (!out) return false;
  auto *src = static_cast<const TemperatureHumiditySensorData *>(
      sensors::registry::latest(SensorKind::TemperatureHumidity, index));
  if (!src) return false;
  *out = *src;
  return sensors::registry::valid(SensorKind::TemperatureHumidity, index);
}

bool sensors::manager::accessSoil(uint8_t index, SoilSensorData *out) {
  if (!out) return false;
  auto *src = static_cast<const SoilSensorData *>(
      sensors::registry::latest(SensorKind::Soil, index));
  if (!src) return false;
  *out = *src;
  return sensors::registry::valid(SensorKind::Soil, index);
}
