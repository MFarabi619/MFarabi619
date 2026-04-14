#include "manager.h"

#include "../hardware/i2c.h"
#include "../networking/modbus.h"

#include <Arduino.h>
#include <math.h>
#include <string.h>

namespace {

SensorInventorySnapshot inventory = {};
CO2SensorData co2_snapshot = {};
VoltageSensorData voltage_snapshot = {};
CurrentSensorData current_snapshot = {};
TemperatureHumiditySensorData temperature_humidity_snapshot[config::temperature_humidity::MAX_SENSORS] = {};
WindSpeedSensorData wind_speed_snapshot = {};
WindDirectionSensorData wind_direction_snapshot = {};
SolarRadiationSensorData solar_radiation_snapshot = {};
BarometricPressureSensorData barometric_pressure_snapshot = {};
SoilSensorData soil_snapshot[8] = {};

bool voltage_valid = false;
bool current_valid = false;
bool co2_valid = false;
bool temperature_humidity_valid[config::temperature_humidity::MAX_SENSORS] = {};
bool wind_speed_valid = false;
bool wind_direction_valid = false;
bool solar_radiation_valid = false;
bool barometric_pressure_valid = false;
bool soil_valid[8] = {};
uint32_t last_poll_ms = 0;

constexpr uint32_t SENSOR_POLL_MS = 5000;

void poll_sensors(void) {
  inventory.temperature_humidity_count = sensors::temperature_and_humidity::sensorCount();
  inventory.soil_probe_count = sensors::soil::probeCount();
  inventory.voltage_available = sensors::voltage::isAvailable();
  inventory.current_available = sensors::current::isAvailable();
  inventory.carbon_dioxide_available = sensors::carbon_dioxide::isAvailable();
  inventory.wind_speed_available = sensors::wind_speed::isAvailable();
  inventory.wind_direction_available = sensors::wind_direction::isAvailable();
  inventory.solar_radiation_available = sensors::solar_radiation::isAvailable();
  inventory.barometric_pressure_available = sensors::barometric_pressure::isAvailable();

  for (uint8_t index = 0; index < inventory.temperature_humidity_count; index++) {
    TemperatureHumiditySensorData sensor_data = {};
    bool ok = sensors::temperature_and_humidity::access(index, &sensor_data);
    temperature_humidity_valid[index] = ok;
    if (ok) {
      temperature_humidity_snapshot[index] = sensor_data;
    }
  }

  VoltageSensorData voltage_data = {};
  voltage_valid = sensors::voltage::access(&voltage_data);
  if (voltage_valid) {
    voltage_snapshot = voltage_data;
  }

  CurrentSensorData current_data = {};
  current_valid = sensors::current::access(&current_data);
  if (current_valid) {
    current_snapshot = current_data;
  }

  CO2SensorData co2_data = {};
  co2_valid = sensors::carbon_dioxide::access(&co2_data);
  if (co2_valid) {
    co2_snapshot = co2_data;
  }

  WindSpeedSensorData wind_speed_data = {};
  wind_speed_valid = sensors::wind_speed::access(&wind_speed_data);
  if (wind_speed_valid) {
    wind_speed_snapshot = wind_speed_data;
  }

  WindDirectionSensorData wind_direction_data = {};
  wind_direction_valid = sensors::wind_direction::access(&wind_direction_data);
  if (wind_direction_valid) {
    wind_direction_snapshot = wind_direction_data;
  }

  SolarRadiationSensorData solar_data = {};
  solar_radiation_valid = sensors::solar_radiation::access(&solar_data);
  if (solar_radiation_valid) {
    solar_radiation_snapshot = solar_data;
  }

  BarometricPressureSensorData pressure_data = {};
  barometric_pressure_valid = sensors::barometric_pressure::access(&pressure_data);
  if (barometric_pressure_valid) {
    barometric_pressure_snapshot = pressure_data;
  }

  for (uint8_t index = 0; index < inventory.soil_probe_count; index++) {
    SoilSensorData soil_data = {};
    bool ok = sensors::soil::access(index, &soil_data);
    soil_valid[index] = ok;
    if (ok) {
      soil_snapshot[index] = soil_data;
    }
  }
}

}

void sensors::manager::initialize() {
  hardware::i2c::runDiscovery();
  memset(&inventory, 0, sizeof(inventory));
  memset(&co2_snapshot, 0, sizeof(co2_snapshot));
  memset(&voltage_snapshot, 0, sizeof(voltage_snapshot));
  memset(&current_snapshot, 0, sizeof(current_snapshot));
  memset(temperature_humidity_snapshot, 0, sizeof(temperature_humidity_snapshot));
  memset(&wind_speed_snapshot, 0, sizeof(wind_speed_snapshot));
  memset(&wind_direction_snapshot, 0, sizeof(wind_direction_snapshot));
  memset(&solar_radiation_snapshot, 0, sizeof(solar_radiation_snapshot));
  memset(soil_snapshot, 0, sizeof(soil_snapshot));
  memset(temperature_humidity_valid, 0, sizeof(temperature_humidity_valid));
  memset(soil_valid, 0, sizeof(soil_valid));

  sensors::temperature_and_humidity::initialize();
  inventory.temperature_humidity_count = sensors::temperature_and_humidity::sensorCount();
  inventory.voltage_available = sensors::voltage::initialize();
  inventory.current_available = sensors::current::initialize();
  inventory.carbon_dioxide_available = sensors::carbon_dioxide::initialize();
  networking::modbus::initialize();
  inventory.wind_speed_available = sensors::wind_speed::initialize();
  if (inventory.wind_speed_available) delay(config::wind::SENSOR_DELAY_MS);
  inventory.wind_direction_available = sensors::wind_direction::initialize();
  inventory.solar_radiation_available = sensors::solar_radiation::initialize();
  inventory.barometric_pressure_available = sensors::barometric_pressure::initialize();
  inventory.soil_probe_count = 0;
  if (sensors::soil::initialize()) {
    inventory.soil_probe_count = sensors::soil::probeCount();
  }
  poll_sensors();
  last_poll_ms = millis();
}

void sensors::manager::service() {
  if (millis() - last_poll_ms < SENSOR_POLL_MS) return;
  last_poll_ms = millis();
  poll_sensors();
}

bool sensors::manager::accessInventory(SensorInventorySnapshot *snapshot) {
  if (!snapshot) return false;
  *snapshot = inventory;
  return true;
}

bool sensors::manager::accessCO2(CO2SensorData *sensor_data) {
  if (!sensor_data) return false;
  *sensor_data = co2_snapshot;
  sensor_data->ok = co2_valid;
  return co2_valid;
}

bool sensors::manager::accessVoltage(VoltageSensorData *sensor_data) {
  if (!sensor_data) return false;
  *sensor_data = voltage_snapshot;
  return voltage_valid;
}

bool sensors::manager::accessWindSpeed(WindSpeedSensorData *sensor_data) {
  if (!sensor_data) return false;
  *sensor_data = wind_speed_snapshot;
  sensor_data->ok = wind_speed_valid;
  return wind_speed_valid;
}

bool sensors::manager::accessWindDirection(WindDirectionSensorData *sensor_data) {
  if (!sensor_data) return false;
  *sensor_data = wind_direction_snapshot;
  sensor_data->ok = wind_direction_valid;
  return wind_direction_valid;
}

bool sensors::manager::accessTemperatureHumidity(uint8_t index,
                                                 TemperatureHumiditySensorData *sensor_data) {
  if (!sensor_data) return false;
  if (index >= inventory.temperature_humidity_count) return false;
  *sensor_data = temperature_humidity_snapshot[index];
  sensor_data->ok = temperature_humidity_valid[index];
  return temperature_humidity_valid[index];
}

bool sensors::manager::accessCurrent(CurrentSensorData *sensor_data) {
  if (!sensor_data) return false;
  *sensor_data = current_snapshot;
  sensor_data->ok = current_valid;
  return current_valid;
}

bool sensors::manager::accessSolarRadiation(SolarRadiationSensorData *sensor_data) {
  if (!sensor_data) return false;
  *sensor_data = solar_radiation_snapshot;
  sensor_data->ok = solar_radiation_valid;
  return solar_radiation_valid;
}

bool sensors::manager::accessSoil(uint8_t index, SoilSensorData *sensor_data) {
  if (!sensor_data) return false;
  if (index >= inventory.soil_probe_count) return false;
  *sensor_data = soil_snapshot[index];
  sensor_data->ok = soil_valid[index];
  return soil_valid[index];
}

bool sensors::manager::accessBarometricPressure(BarometricPressureSensorData *sensor_data) {
  if (!sensor_data) return false;
  *sensor_data = barometric_pressure_snapshot;
  sensor_data->ok = barometric_pressure_valid;
  return barometric_pressure_valid;
}
