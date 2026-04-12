#pragma once

#include <RTClib.h>

extern RTC_DS3231 RTC;

bool rtcInitialize() noexcept;

namespace services::rtc {
#ifdef PIO_UNIT_TESTING
void test();
#endif
}
