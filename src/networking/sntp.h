#ifndef NETWORKING_SNTP_H
#define NETWORKING_SNTP_H

#include "../config.h"
#include <stdbool.h>
#include <stdint.h>

// Start NTP sync. Call after WiFi is connected.
// Configures timezone and NTP servers, then syncs.
// Updates the DS3231 RTC with UTC time on success.
bool sntp_sync(void);

// Returns true if NTP has synced at least once.
bool sntp_is_synced(void);

// Get current local time as formatted string (respects CONFIG_TIME_ZONE).
const char *sntp_local_time_string(void);

// Get current UTC epoch from system time (set by NTP).
uint32_t sntp_utc_epoch(void);

#endif // NETWORKING_SNTP_H
