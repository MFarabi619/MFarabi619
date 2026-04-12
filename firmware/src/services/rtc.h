#pragma once

#include <stdint.h>

struct RTCSnapshot {
  bool valid;
  char iso8601[32];
  float temperature_celsius;
};

namespace services::rtc {
bool initialize() noexcept;
bool isValid() noexcept;
bool setEpoch(uint32_t epoch) noexcept;
uint32_t accessEpoch() noexcept;
bool accessSnapshot(RTCSnapshot *snapshot) noexcept;
#ifdef PIO_UNIT_TESTING
void test();
#endif
}
