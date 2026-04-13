#include "manager.h"

#include "../networking/modbus.h"

#include <Arduino.h>
#include <math.h>
#include <string.h>

namespace {

SensorInventorySnapshot inventory = {};
CO2SensorData co2_snapshot = {};
VoltageSensorData voltage_snapshot = {};
TemperatureHumiditySensorData temperature_humidity_snapshot[config::temperature_humidity::MAX_SENSORS] = {};
WindSpeedSensorData wind_speed_snapshot = {};
WindDirectionSensorData wind_direction_snapshot = {};

bool voltage_valid = false;
bool co2_valid = false;
bool temperature_humidity_valid[config::temperature_humidity::MAX_SENSORS] = {};
bool wind_speed_valid = false;
bool wind_direction_valid = false;
uint32_t last_poll_ms = 0;

constexpr uint32_t SENSOR_POLL_MS = 5000;

void poll_sensors(void) {
  inventory.temperature_humidity_count = sensors::temperature_and_humidity::sensorCount();
  inventory.voltage_available = sensors::voltage::isReady();
  inventory.carbon_dioxide_available = sensors::carbon_dioxide::isAvailable();
  inventory.wind_speed_available = sensors::wind_speed::isAvailable();
  inventory.wind_direction_available = sensors::wind_direction::isAvailable();

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

  CO2SensorData co2_data = {};
  co2_valid = sensors::carbon_dioxide::accessReading(&co2_data);
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
}

}

void sensors::manager::initialize() {
  memset(&inventory, 0, sizeof(inventory));
  memset(&co2_snapshot, 0, sizeof(co2_snapshot));
  memset(&voltage_snapshot, 0, sizeof(voltage_snapshot));
  memset(temperature_humidity_snapshot, 0, sizeof(temperature_humidity_snapshot));
  memset(&wind_speed_snapshot, 0, sizeof(wind_speed_snapshot));
  memset(&wind_direction_snapshot, 0, sizeof(wind_direction_snapshot));
  memset(temperature_humidity_valid, 0, sizeof(temperature_humidity_valid));

  sensors::temperature_and_humidity::discover();
  inventory.temperature_humidity_count = sensors::temperature_and_humidity::sensorCount();
  inventory.voltage_available = sensors::voltage::initialize();
  inventory.carbon_dioxide_available = sensors::carbon_dioxide::initialize();
  networking::modbus::initialize();
  inventory.wind_speed_available = sensors::wind_speed::initialize();
  if (inventory.wind_speed_available) delay(config::wind::SENSOR_DELAY_MS);
  inventory.wind_direction_available = sensors::wind_direction::initialize();
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
