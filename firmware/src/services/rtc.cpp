#include "rtc.h"

#include <Arduino.h>

RTC_DS3231 RTC;

bool rtcInitialize() noexcept {
    if (!RTC.begin()) return false;
    if (RTC.lostPower()) {
        RTC.adjust(DateTime(F(__DATE__), F(__TIME__)));
        delay(10);
    }
    DateTime now = RTC.now();
    return now.isValid() && now.year() >= 2020 && now.year() <= 2099;
}

#ifdef PIO_UNIT_TESTING

#include "../testing/it.h"
#include "../testing/i2c_helpers.h"

static void rtc_test_init() {
    test_ensure_wire0();
    TEST_MESSAGE("user initializes the RTC");
    TEST_ASSERT_TRUE_MESSAGE(rtcInitialize(), "device: rtcInitialize() failed");
    TEST_MESSAGE("RTC initialized");
}

static void rtc_test_oscillator() {
    TEST_MESSAGE("user checks if the RTC oscillator is running");
    rtcInitialize();
    TEST_ASSERT_FALSE_MESSAGE(RTC.lostPower(),
        "device: oscillator stopped — battery may be dead");
    TEST_MESSAGE("oscillator is running");
}

static void rtc_test_reads_time() {
    TEST_MESSAGE("user reads the current time from the RTC");
    rtcInitialize();
    DateTime now = RTC.now();
    TEST_ASSERT_TRUE_MESSAGE(now.isValid(), "device: DateTime is invalid");
    uint32_t epoch = now.unixtime();
    TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(1577836800, epoch,
        "device: epoch is before 2020 — RTC may not be set");
    String ts = now.timestamp();
    TEST_ASSERT_TRUE_MESSAGE(ts.length() > 0, "device: timestamp is empty");
    TEST_MESSAGE(ts.c_str());
}

static void rtc_test_reads_temperature() {
    TEST_MESSAGE("user reads temperature from the RTC");
    rtcInitialize();
    float temp = RTC.getTemperature();
    TEST_ASSERT_FLOAT_WITHIN_MESSAGE(60.0f, 22.5f, temp,
        "device: temperature outside plausible range");
    char msg[32];
    snprintf(msg, sizeof(msg), "%.2f C", temp);
    TEST_MESSAGE(msg);
}

static void rtc_test_set_and_restore_epoch() {
    TEST_MESSAGE("user sets epoch, verifies, then restores");
    rtcInitialize();

    uint32_t original = RTC.now().unixtime();
    uint32_t test_epoch = 1712318400; // 2024-04-05 12:00:00 UTC
    RTC.adjust(DateTime(test_epoch));
    delay(100);

    uint32_t readback = RTC.now().unixtime();
    TEST_ASSERT_UINT32_WITHIN_MESSAGE(2, test_epoch, readback,
        "device: epoch readback doesn't match");

    RTC.adjust(DateTime(original));
    delay(100);
    TEST_MESSAGE("epoch set/read verified and original time restored");
}

static void rtc_test_alarm1() {
    TEST_MESSAGE("user enables alarm 1 (every second) and checks if it fires");
    rtcInitialize();

    RTC.clearAlarm(1);
    RTC.setAlarm1(DateTime((uint32_t)0), DS3231_A1_PerSecond);
    delay(1100);
    TEST_ASSERT_TRUE_MESSAGE(RTC.alarmFired(1),
        "device: alarm 1 did not fire after 1.1 seconds");

    RTC.disableAlarm(1);
    RTC.clearAlarm(1);
    TEST_MESSAGE("alarm 1 fired and was disabled");
}

static void rtc_test_set_from_compile_time() {
    TEST_MESSAGE("user seeds RTC from compile time");
    test_ensure_wire0();

    uint32_t original = RTC.now().unixtime();
    RTC.adjust(DateTime(F(__DATE__), F(__TIME__)));
    delay(10);

    DateTime now = RTC.now();
    TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(1577836800, now.unixtime(),
        "device: epoch after compile-time seed is before 2020");

    String ts = now.timestamp();
    TEST_ASSERT_TRUE_MESSAGE(ts.length() > 0, "device: timestamp empty");
    TEST_MESSAGE(ts.c_str());

    RTC.adjust(DateTime(original));
    delay(10);
}

static void rtc_test_alarm_disable_clears() {
    TEST_MESSAGE("user enables alarm 1, disables it, verifies it stops");
    test_ensure_wire0();
    rtcInitialize();

    RTC.clearAlarm(1);
    RTC.setAlarm1(DateTime((uint32_t)0), DS3231_A1_PerSecond);
    delay(1100);
    TEST_ASSERT_TRUE_MESSAGE(RTC.alarmFired(1),
        "device: alarm 1 should have fired");

    RTC.disableAlarm(1);
    RTC.clearAlarm(1);
    delay(1100);
    TEST_ASSERT_FALSE_MESSAGE(RTC.alarmFired(1),
        "device: alarm 1 should not fire after disable");

    TEST_MESSAGE("alarm disable verified");
}

void services::rtc::test() {
    it("user observes that the RTC initializes",
       rtc_test_init);
    it("user observes that the oscillator is running",
       rtc_test_oscillator);
    it("user observes that the RTC reads a valid time",
       rtc_test_reads_time);
    it("user observes that the RTC reads a plausible temperature",
       rtc_test_reads_temperature);
    it("user observes that epoch can be set and restored",
       rtc_test_set_and_restore_epoch);
    it("user observes that alarm 1 fires within 1 second",
       rtc_test_alarm1);
    it("user observes that compile-time seed produces valid time",
       rtc_test_set_from_compile_time);
    it("user observes that disabling alarm 1 stops it",
       rtc_test_alarm_disable_clears);
}

#endif
