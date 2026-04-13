#ifndef SENSORS_WIND_SPEED_H
#define SENSORS_WIND_SPEED_H

#include <stdbool.h>

struct WindSpeedSensorData {
  float kilometers_per_hour;
  bool ok;
};

namespace sensors::wind_speed {

bool initialize();
bool isAvailable();
bool access(WindSpeedSensorData *sensor_data);

}

#endif
