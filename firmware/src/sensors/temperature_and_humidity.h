#ifndef SENSORS_TEMPERATURE_AND_HUMIDITY_H
#define SENSORS_TEMPERATURE_AND_HUMIDITY_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

struct TemperatureHumiditySensorData {
  float temperature_celsius;
  float relative_humidity_percent;
  const char *model;
  bool ok;
};

namespace sensors::temperature_and_humidity {

bool initialize();
uint8_t sensorCount();

bool access(uint8_t index,
                          TemperatureHumiditySensorData *sensor_data);

uint8_t accessAll(TemperatureHumiditySensorData *sensor_data,
                                bool *read_ok,
                                uint8_t max_count);

#ifdef PIO_UNIT_TESTING
void test();
#endif

}

#endif
