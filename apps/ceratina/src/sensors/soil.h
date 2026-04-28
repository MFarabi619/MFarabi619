#pragma once
#include <stdbool.h>
#include <stdint.h>

struct SoilSensorData {
  uint8_t slave_id;
  const char *model;
  float temperature_celsius;
  float moisture_percent;
  uint16_t conductivity;
  uint16_t salinity;
  uint16_t tds;
  float ph;
  bool has_conductivity;
  bool has_salinity;
  bool has_tds;
  bool has_ph;
  float temperature_calibration;
  float moisture_calibration;
  uint16_t conductivity_calibration;
  float conductivity_temperature_coefficient;
  float salinity_coefficient;
  float tds_coefficient;
  bool has_calibration;
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

