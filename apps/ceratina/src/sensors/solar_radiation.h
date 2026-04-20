#pragma once
#include <stdbool.h>
#include <stdint.h>

struct SolarRadiationSensorData {
  uint16_t watts_per_square_meter;
  bool ok;
};

namespace sensors::solar_radiation {

bool initialize();
bool isAvailable();
bool access(SolarRadiationSensorData *sensor_data);

#ifdef PIO_UNIT_TESTING
void test();
#endif

}

