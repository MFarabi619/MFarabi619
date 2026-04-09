#ifndef DRIVERS_DS3231_H
#define DRIVERS_DS3231_H

#include <stdint.h>
#include <stdbool.h>

// ─────────────────────────────────────────────────────────────────────────────
//  Core
// ─────────────────────────────────────────────────────────────────────────────

bool ds3231_init(void);
bool ds3231_oscillator_ok(void);
uint32_t ds3231_unixtime(void);
float ds3231_temperature(void);
const char *ds3231_time_string(void);

// ─────────────────────────────────────────────────────────────────────────────
//  Time setting
// ─────────────────────────────────────────────────────────────────────────────

void ds3231_set_epoch(uint32_t epoch);
void ds3231_set_from_compile_time(void);

// ─────────────────────────────────────────────────────────────────────────────
//  Alarms (INT/SQW pin active-low on fire)
// ─────────────────────────────────────────────────────────────────────────────

void ds3231_alarm1_every_second(void);
void ds3231_alarm1_at(uint8_t hour, uint8_t minute, uint8_t second);
void ds3231_alarm1_disable(void);
bool ds3231_alarm1_fired(void);

void ds3231_alarm2_every_minute(void);
void ds3231_alarm2_at(uint8_t hour, uint8_t minute);
void ds3231_alarm2_disable(void);
bool ds3231_alarm2_fired(void);

#endif // DRIVERS_DS3231_H
