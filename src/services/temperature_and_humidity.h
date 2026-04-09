#ifndef SERVICES_TEMPERATURE_AND_HUMIDITY_H
#define SERVICES_TEMPERATURE_AND_HUMIDITY_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

// Scan all TCA9548A mux channels for CHT832X sensors at
// CONFIG_TEMPERATURE_HUMIDITY_I2C_ADDR. Returns count of sensors found (0..8).
uint8_t temperature_and_humidity_discover(void);

// Number of sensors found by the last discover() call.
uint8_t temperature_and_humidity_sensor_count(void);

// Read a single sensor at logical `index` (0-based, maps to a mux channel).
// Uses exclusive selectChannel() — caller or read_all() is responsible for
// calling tca9548a_disable_all() when done with the mux.
// Blocks ~60ms for the measurement. Returns true on success.
bool temperature_and_humidity_read(uint8_t index,
                                   float *temperature_celsius,
                                   float *relative_humidity_percent);

// Read all discovered sensors. Caller-allocated arrays must have at least
// temperature_and_humidity_sensor_count() elements.
// read_ok[i] indicates per-sensor success.
// Returns count of successful reads.
uint8_t temperature_and_humidity_read_all(float *temperatures,
                                          float *humidities,
                                          bool *read_ok,
                                          uint8_t max_count);

#ifdef PIO_UNIT_TESTING
void temperature_and_humidity_run_tests(void);
#endif

#endif // SERVICES_TEMPERATURE_AND_HUMIDITY_H
