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

bool initialize();
[[nodiscard]] bool accessReading(CO2SensorData *sensor_data);
bool accessConfig(Co2Config *config);
[[nodiscard]] bool isAvailable();
bool enable();
bool disable();
bool configureInterval(uint16_t seconds);
bool configureAutoCalibration(bool enabled);
bool configureTemperatureOffset(float celsius);
bool configureAltitude(uint16_t meters);
bool configureRecalibration(uint16_t co2_reference_ppm);

#ifdef PIO_UNIT_TESTING
void test();
#endif

}

#endif
