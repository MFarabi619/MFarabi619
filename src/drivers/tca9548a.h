#ifndef DRIVERS_TCA9548A_H
#define DRIVERS_TCA9548A_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

bool tca9548a_init(void);
bool tca9548a_is_connected(void);
uint8_t tca9548a_channel_count(void);

bool tca9548a_select(uint8_t channel);
bool tca9548a_enable(uint8_t channel);
bool tca9548a_disable(uint8_t channel);
bool tca9548a_disable_all(void);
bool tca9548a_is_enabled(uint8_t channel);
uint8_t tca9548a_get_mask(void);

// Returns bitmask of channels where `addr` was found
uint8_t tca9548a_find(uint8_t addr);

// Scan all channels, format results into buf. Returns strlen.
int tca9548a_scan_all(char *buf, size_t buf_size);

#ifdef PIO_UNIT_TESTING
void tca9548a_run_tests(void);
#endif

#endif // DRIVERS_TCA9548A_H
