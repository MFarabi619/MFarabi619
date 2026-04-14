#pragma once

#include <stdint.h>

struct BarometricPressureSensorData {
    float pressure_hpa;
    float temperature_celsius;
    const char *model;
    bool ok;
};

namespace sensors::barometric_pressure {

bool initialize();
bool access(BarometricPressureSensorData *data);
bool isAvailable();

#ifdef PIO_UNIT_TESTING
void test();
#endif

}
