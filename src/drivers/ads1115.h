#ifndef DRIVERS_ADS1115_H
#define DRIVERS_ADS1115_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

bool ads1115_init(void);
bool ads1115_begin(void);
const char *ads1115_gain_label(void);

// Read all channels into caller-allocated array.
// channel_count must be >= CONFIG_VOLTAGE_MONITOR_CHANNEL_COUNT.
bool ads1115_read(float *channel_volts, size_t channel_count);

#ifdef PIO_UNIT_TESTING
void ads1115_run_tests(void);
#endif

#endif // DRIVERS_ADS1115_H
