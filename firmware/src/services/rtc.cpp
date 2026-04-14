#include "rtc.h"

#include <Arduino.h>
#include <RTClib.h>

namespace {

RTC_DS3231 rtc_device;

}

bool services::rtc::initialize() {
    if (!rtc_device.begin()) return false;
    if (rtc_device.lostPower()) {
        rtc_device.adjust(DateTime(F(__DATE__), F(__TIME__)));
        delay(10);
    }
    DateTime now = rtc_device.now();
    return now.isValid() && now.year() >= 2020 && now.year() <= 2099;
}

bool services::rtc::isValid() {
    DateTime now = rtc_device.now();
    return !rtc_device.lostPower() && now.isValid() && now.year() >= 2020 && now.year() <= 2099;
}

bool services::rtc::setEpoch(uint32_t epoch) {
    rtc_device.adjust(DateTime(epoch));
    delay(10);
    return true;
}

uint32_t services::rtc::accessEpoch() {
    return rtc_device.now().unixtime();
}

bool services::rtc::accessSnapshot(RTCSnapshot *snapshot) {
    if (!snapshot) return false;
    memset(snapshot, 0, sizeof(*snapshot));

    snapshot->valid = services::rtc::isValid();
    snapshot->temperature_celsius = rtc_device.getTemperature();

    if (snapshot->valid) {
        strlcpy(snapshot->iso8601, rtc_device.now().timestamp().c_str(), sizeof(snapshot->iso8601));
    }

    return snapshot->valid;
}

#ifdef PIO_UNIT_TESTING

#include "../testing/it.h"
#include "../testing/i2c_helpers.h"
#include "../hardware/i2c.h"

static void rtc_test_init() {
    hardware::i2c::initialize();
    hardware::i2c::DiscoveredDevice dev = {};
    if (!hardware::i2c::findDevice(0x68, &dev)) {
        TEST_IGNORE_MESSAGE("no DS3231 found on I2C");
        return;
    }
    TEST_MESSAGE("user initializes the RTC");
    TEST_ASSERT_TRUE_MESSAGE(services::rtc::initialize(), "device: rtcInitialize() failed");
    TEST_MESSAGE("RTC initialized");
}

static void rtc_test_oscillator() {
    TEST_MESSAGE("user checks if the RTC oscillator is running");
    services::rtc::initialize();
    TEST_ASSERT_FALSE_MESSAGE(rtc_device.lostPower(),
        "device: oscillator stopped — battery may be dead");
    TEST_MESSAGE("oscillator is running");
}

static void rtc_test_reads_time() {
    TEST_MESSAGE("user reads the current time from the RTC");
    services::rtc::initialize();
    DateTime now = rtc_device.now();
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
    services::rtc::initialize();
    float temp = rtc_device.getTemperature();
    TEST_ASSERT_FLOAT_WITHIN_MESSAGE(60.0f, 22.5f, temp,
        "device: temperature outside plausible range");
    char msg[32];
    snprintf(msg, sizeof(msg), "%.2f C", temp);
    TEST_MESSAGE(msg);
}

static void rtc_test_set_and_restore_epoch() {
    TEST_MESSAGE("user sets epoch, verifies, then restores");
    services::rtc::initialize();

    uint32_t original = rtc_device.now().unixtime();
    uint32_t test_epoch = 1712318400; // 2024-04-05 12:00:00 UTC
    rtc_device.adjust(DateTime(test_epoch));
    delay(100);

    uint32_t readback = rtc_device.now().unixtime();
    TEST_ASSERT_UINT32_WITHIN_MESSAGE(2, test_epoch, readback,
        "device: epoch readback doesn't match");

    rtc_device.adjust(DateTime(original));
    delay(100);
    TEST_MESSAGE("epoch set/read verified and original time restored");
}

static void rtc_test_alarm1() {
    TEST_MESSAGE("user enables alarm 1 (every second) and checks if it fires");
    services::rtc::initialize();

    rtc_device.clearAlarm(1);
    rtc_device.setAlarm1(DateTime((uint32_t)0), DS3231_A1_PerSecond);
    delay(1100);
    TEST_ASSERT_TRUE_MESSAGE(rtc_device.alarmFired(1),
        "device: alarm 1 did not fire after 1.1 seconds");

    rtc_device.disableAlarm(1);
    rtc_device.clearAlarm(1);
    TEST_MESSAGE("alarm 1 fired and was disabled");
}

static void rtc_test_set_from_compile_time() {
    TEST_MESSAGE("user seeds RTC from compile time");
    test_ensure_wire0();

    uint32_t original = rtc_device.now().unixtime();
    rtc_device.adjust(DateTime(F(__DATE__), F(__TIME__)));
    delay(10);

    DateTime now = rtc_device.now();
    TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(1577836800, now.unixtime(),
        "device: epoch after compile-time seed is before 2020");

    String ts = now.timestamp();
    TEST_ASSERT_TRUE_MESSAGE(ts.length() > 0, "device: timestamp empty");
    TEST_MESSAGE(ts.c_str());

    rtc_device.adjust(DateTime(original));
    delay(10);
}

static void rtc_test_alarm_disable_clears() {
    TEST_MESSAGE("user enables alarm 1, disables it, verifies it stops");
    test_ensure_wire0();
    services::rtc::initialize();

    rtc_device.clearAlarm(1);
    rtc_device.setAlarm1(DateTime((uint32_t)0), DS3231_A1_PerSecond);
    delay(1100);
    TEST_ASSERT_TRUE_MESSAGE(rtc_device.alarmFired(1),
        "device: alarm 1 should have fired");

    rtc_device.disableAlarm(1);
    rtc_device.clearAlarm(1);
    delay(1100);
    TEST_ASSERT_FALSE_MESSAGE(rtc_device.alarmFired(1),
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
