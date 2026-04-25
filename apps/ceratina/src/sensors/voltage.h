#pragma once
#include <config.h>

struct VoltageSensorData {
  float channel_volts[config::voltage::CHANNEL_COUNT];
  float temperature_celsius[config::voltage::CHANNEL_COUNT];
};

namespace sensors::voltage {

void registerProbes();
bool isAvailable();
bool access(VoltageSensorData *sensor_data);
const char *accessGainLabel();

#ifdef PIO_UNIT_TESTING
void test();
#endif

}

