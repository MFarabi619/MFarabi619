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

bool initialize() noexcept;
[[nodiscard]] bool isReady() noexcept;
[[nodiscard]] bool access(VoltageSensorData *sensor_data) noexcept;
[[nodiscard]] const char *accessGainLabel() noexcept;

#ifdef PIO_UNIT_TESTING
void test() noexcept;
#endif

}

#endif
