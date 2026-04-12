#ifndef SENSORS_MANAGER_H
#define SENSORS_MANAGER_H

#include "carbon_dioxide.h"
#include "temperature_and_humidity.h"
#include "voltage.h"

struct SensorInventorySnapshot {
  uint8_t temperature_humidity_count;
  bool voltage_available;
  bool carbon_dioxide_available;
};

namespace sensors::manager {

void initialize() noexcept;
void service() noexcept;
bool accessInventory(SensorInventorySnapshot *snapshot) noexcept;
bool accessCO2(CO2SensorData *sensor_data) noexcept;
bool accessVoltage(VoltageSensorData *sensor_data) noexcept;
bool accessTemperatureHumidity(uint8_t index,
                               TemperatureHumiditySensorData *sensor_data) noexcept;

}

#endif
