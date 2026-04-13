#ifndef SENSORS_SOIL_H
#define SENSORS_SOIL_H

#include <stdbool.h>
#include <stdint.h>

struct SoilSensorData {
  float temperature_celsius;
  float moisture_percent;
  uint16_t conductivity;
  uint16_t salinity;
  uint16_t tds;
  uint8_t slave_id;
  bool ok;
};

namespace sensors::soil {

bool initialize();
bool isAvailable();
uint8_t probeCount();
bool access(uint8_t index, SoilSensorData *sensor_data);

#ifdef PIO_UNIT_TESTING
void test();
#endif

}

#endif
