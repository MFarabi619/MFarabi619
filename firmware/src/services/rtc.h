#pragma once

#include <stdint.h>

struct RTCSnapshot {
  bool valid;
  char iso8601[32];
  float temperature_celsius;
};

namespace services::rtc {
bool initialize();
bool isValid();
bool setEpoch(uint32_t epoch);
uint32_t accessEpoch();
bool accessSnapshot(RTCSnapshot *snapshot);
#ifdef PIO_UNIT_TESTING
void test();
#endif
}
