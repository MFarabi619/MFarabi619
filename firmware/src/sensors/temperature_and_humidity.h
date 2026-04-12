#ifndef SENSORS_TEMPERATURE_AND_HUMIDITY_H
#define SENSORS_TEMPERATURE_AND_HUMIDITY_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

struct TemperatureHumiditySensorData {
  float temperature_celsius;
  float relative_humidity_percent;
  bool ok;
};

namespace sensors::temperature_and_humidity {

uint8_t discover() noexcept;
[[nodiscard]] uint8_t sensorCount() noexcept;

[[nodiscard]] bool access(uint8_t index,
                          TemperatureHumiditySensorData *sensor_data) noexcept;

[[nodiscard]] uint8_t accessAll(TemperatureHumiditySensorData *sensor_data,
                                bool *read_ok,
                                uint8_t max_count) noexcept;

#ifdef PIO_UNIT_TESTING
void test() noexcept;
#endif

}

#endif
