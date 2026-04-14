#pragma once
#include <stdbool.h>
#include <stdint.h>

struct WindDirectionSensorData {
  float degrees;
  uint8_t slice;
  bool ok;
};

namespace sensors::wind_direction {

bool initialize();
bool isAvailable();
bool access(WindDirectionSensorData *sensor_data);

}

