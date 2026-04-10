#ifndef SERVICES_CO2_H
#define SERVICES_CO2_H

#include <stdbool.h>
#include <stdint.h>

struct Co2Reading {
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

bool co2_init(void);
bool co2_begin(void);
bool co2_read(Co2Reading *reading);
bool co2_start(void);
bool co2_stop(void);
bool co2_get_config(Co2Config *config);
bool co2_set_measurement_interval(uint16_t seconds);
bool co2_set_auto_calibration(bool enabled);
bool co2_set_temperature_offset(float celsius);
bool co2_set_altitude(uint16_t meters);
bool co2_force_recalibration(uint16_t co2_reference_ppm);
bool co2_is_available(void);

#ifdef PIO_UNIT_TESTING
void co2_run_tests(void);
#endif

#endif
