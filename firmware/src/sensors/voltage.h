#ifndef SENSORS_VOLTAGE_H
#define SENSORS_VOLTAGE_H

#include "../config.h"

struct VoltageSensorData {
  float channel_volts[config::voltage::CHANNEL_COUNT];
};

namespace sensors::voltage {

bool initialize();
bool isAvailable();
bool access(VoltageSensorData *sensor_data);
const char *accessGainLabel();

#ifdef PIO_UNIT_TESTING
void test();
#endif

}

#endif
