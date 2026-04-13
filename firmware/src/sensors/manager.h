#ifndef SENSORS_MANAGER_H
#define SENSORS_MANAGER_H

#include "carbon_dioxide.h"
#include "temperature_and_humidity.h"
#include "voltage.h"
#include "wind_direction.h"
#include "wind_speed.h"

struct SensorInventorySnapshot {
  uint8_t temperature_humidity_count;
  bool voltage_available;
  bool carbon_dioxide_available;
  bool wind_speed_available;
  bool wind_direction_available;
};

namespace sensors::manager {

void initialize();
void service();
bool accessInventory(SensorInventorySnapshot *snapshot);
bool accessCO2(CO2SensorData *sensor_data);
bool accessVoltage(VoltageSensorData *sensor_data);
bool accessWindSpeed(WindSpeedSensorData *sensor_data);
bool accessWindDirection(WindDirectionSensorData *sensor_data);
bool accessTemperatureHumidity(uint8_t index,
                               TemperatureHumiditySensorData *sensor_data);

}

#endif
