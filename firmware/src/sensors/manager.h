#ifndef SENSORS_MANAGER_H
#define SENSORS_MANAGER_H

#include "barometric_pressure.h"
#include "carbon_dioxide.h"
#include "current.h"
#include "soil.h"
#include "solar_radiation.h"
#include "temperature_and_humidity.h"
#include "voltage.h"
#include "wind_direction.h"
#include "wind_speed.h"

struct SensorInventorySnapshot {
  uint8_t temperature_humidity_count;
  uint8_t soil_probe_count;
  bool voltage_available;
  bool current_available;
  bool carbon_dioxide_available;
  bool wind_speed_available;
  bool wind_direction_available;
  bool solar_radiation_available;
  bool barometric_pressure_available;
};

namespace sensors::manager {

void initialize();
void service();
bool accessInventory(SensorInventorySnapshot *snapshot);
bool accessCO2(CO2SensorData *sensor_data);
bool accessVoltage(VoltageSensorData *sensor_data);
bool accessCurrent(CurrentSensorData *sensor_data);
bool accessWindSpeed(WindSpeedSensorData *sensor_data);
bool accessWindDirection(WindDirectionSensorData *sensor_data);
bool accessSolarRadiation(SolarRadiationSensorData *sensor_data);
bool accessSoil(uint8_t index, SoilSensorData *sensor_data);
bool accessTemperatureHumidity(uint8_t index,
                               TemperatureHumiditySensorData *sensor_data);
bool accessBarometricPressure(BarometricPressureSensorData *sensor_data);

}

#endif
