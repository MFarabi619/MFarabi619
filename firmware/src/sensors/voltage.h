#ifndef SENSORS_VOLTAGE_H
#define SENSORS_VOLTAGE_H

#include "../config.h"
#include <Adafruit_ADS1X15.h>
#include <stddef.h>

struct VoltageSensorData {
  float channel_volts[config::voltage::CHANNEL_COUNT];
};

namespace sensors::voltage {

extern Adafruit_ADS1115 ADC;

bool initialize();
bool isAvailable();
bool access(VoltageSensorData *sensor_data);
const char *accessGainLabel();

#ifdef PIO_UNIT_TESTING
void test();
#endif

}

#endif
