#pragma once
#include <stdbool.h>

struct WindSpeedSensorData {
  float kilometers_per_hour;
  bool ok;
};

namespace sensors::wind_speed {

bool initialize();
bool isAvailable();
bool access(WindSpeedSensorData *sensor_data);

#ifdef PIO_UNIT_TESTING
void test();
#endif

}
