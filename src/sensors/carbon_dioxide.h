#ifndef SENSORS_CARBON_DIOXIDE_H
#define SENSORS_CARBON_DIOXIDE_H

#include <stdbool.h>
#include <stdint.h>

struct CO2SensorData {
  float co2_ppm;
  float temperature_celsius;
  float relative_humidity_percent;
  const char *model;
  bool ok;
};

struct Co2Config {
  const char *model;
  bool measuring;
  uint16_t measurement_interval_seconds;
  bool auto_calibration_enabled;
  float temperature_offset_celsius;
  uint16_t altitude_meters;
};

namespace sensors::carbon_dioxide {

bool initialize() noexcept;
[[nodiscard]] bool accessReading(CO2SensorData *sensor_data) noexcept;
bool accessConfig(Co2Config *config) noexcept;
[[nodiscard]] bool isAvailable() noexcept;
bool enable() noexcept;
bool disable() noexcept;
bool configureInterval(uint16_t seconds) noexcept;
bool configureAutoCalibration(bool enabled) noexcept;
bool configureTemperatureOffset(float celsius) noexcept;
bool configureAltitude(uint16_t meters) noexcept;
bool configureRecalibration(uint16_t co2_reference_ppm) noexcept;

#ifdef PIO_UNIT_TESTING
void test() noexcept;
#endif

}

#endif
