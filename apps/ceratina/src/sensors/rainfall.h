#pragma once
#include <stdbool.h>

struct RainfallSensorData {
  float millimeters;
  bool ok;
};

namespace sensors::rainfall {

bool initialize();
bool isAvailable();
bool access(RainfallSensorData *sensor_data);
bool clear();

#ifdef PIO_UNIT_TESTING
void test();
#endif

}
