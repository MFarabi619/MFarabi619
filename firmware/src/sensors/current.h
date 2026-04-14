#ifndef SENSORS_CURRENT_H
#define SENSORS_CURRENT_H

#include <stdbool.h>

struct CurrentSensorData {
  float current_mA;
  float bus_voltage_V;
  float shunt_voltage_mV;
  float power_mW;
  float energy_J;
  float charge_C;
  float die_temperature_C;
  bool ok;
};

namespace sensors::current {

bool initialize();
bool isAvailable();
bool access(CurrentSensorData *sensor_data);

#ifdef PIO_UNIT_TESTING
void test();
#endif

}

#endif
