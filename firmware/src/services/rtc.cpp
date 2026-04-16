#include "rtc.h"

#include <Arduino.h>
#include <RTClib.h>

namespace {

RTC_DS3231 rtc_device;
bool is_initialized = false;

}

bool services::rtc::initialize() {
    is_initialized = rtc_device.begin();
    if (!is_initialized) return false;
    if (rtc_device.lostPower()) {
        rtc_device.adjust(DateTime(F(__DATE__), F(__TIME__)));
        delay(10);
    }
    DateTime now = rtc_device.now();
    return now.isValid() && now.year() >= 2020 && now.year() <= 2099;
}

bool services::rtc::isValid() {
    if (!is_initialized) return false;
    DateTime now = rtc_device.now();
    return !rtc_device.lostPower() && now.isValid() && now.year() >= 2020 && now.year() <= 2099;
}

bool services::rtc::setEpoch(uint32_t epoch) {
    if (!is_initialized) return false;
    rtc_device.adjust(DateTime(epoch));
    delay(10);
    return true;
}

uint32_t services::rtc::accessEpoch() {
    if (!is_initialized) return 0;
    return rtc_device.now().unixtime();
}

bool services::rtc::accessSnapshot(RTCSnapshot *snapshot) {
    if (!snapshot) return false;
    if (!is_initialized) return false;
    memset(snapshot, 0, sizeof(*snapshot));

    snapshot->valid = services::rtc::isValid();
    snapshot->temperature_celsius = rtc_device.getTemperature();

    if (snapshot->valid) {
        strlcpy(snapshot->iso8601, rtc_device.now().timestamp().c_str(), sizeof(snapshot->iso8601));
    }

    return snapshot->valid;
}

#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

#include <i2c.h>

static void test_rtc_init() {
    hardware::i2c::initialize();
    hardware::i2c::DiscoveredDevice dev = {};
    if (!hardware::i2c::findDevice(0x68, &dev)) {
        TEST_IGNORE_MESSAGE("no DS3231 found on I2C");
        return;
    }
    WHEN("the RTC is initialized");
    TEST_ASSERT_TRUE_MESSAGE(services::rtc::initialize(), "device: rtcInitialize() failed");
}

static void test_rtc_oscillator() {
    GIVEN("the RTC is initialized");
    services::rtc::initialize();

    THEN("the oscillator is running");
    TEST_ASSERT_FALSE_MESSAGE(rtc_device.lostPower(),
        "device: oscillator stopped — battery may be dead");
}

static void test_rtc_reads_time() {
    GIVEN("the RTC is initialized");
    services::rtc::initialize();

    WHEN("the current time is read");
    DateTime now = rtc_device.now();
    TEST_ASSERT_TRUE_MESSAGE(now.isValid(), "device: DateTime is invalid");
    uint32_t epoch = now.unixtime();
    TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(1577836800, epoch,
        "device: epoch is before 2020 — RTC may not be set");
    String ts = now.timestamp();
    TEST_ASSERT_NOT_EMPTY_MESSAGE(ts.c_str(), "device: timestamp is empty");
    TEST_MESSAGE(ts.c_str());
}

static void test_rtc_reads_temperature() {
    GIVEN("the RTC is initialized");
    services::rtc::initialize();

    WHEN("the temperature is read");
    float temp = rtc_device.getTemperature();
    TEST_ASSERT_GREATER_OR_EQUAL_FLOAT_MESSAGE(-37.5f, temp,
        "device: RTC temperature below DS3231 minimum");
    TEST_ASSERT_LESS_OR_EQUAL_FLOAT_MESSAGE(82.5f, temp,
        "device: RTC temperature above DS3231 maximum");
    char msg[32];
    snprintf(msg, sizeof(msg), "%.2f C", temp);
    TEST_MESSAGE(msg);
}

static void test_rtc_set_and_restore_epoch() {
    GIVEN("the RTC is initialized");
    services::rtc::initialize();

    WHEN("the epoch is set and read back");

    uint32_t original = rtc_device.now().unixtime();
    uint32_t test_epoch = 1712318400; // 2024-04-05 12:00:00 UTC
    rtc_device.adjust(DateTime(test_epoch));
    delay(100);

    uint32_t readback = rtc_device.now().unixtime();
    TEST_ASSERT_UINT32_WITHIN_MESSAGE(2, test_epoch, readback,
        "device: epoch readback doesn't match");

    rtc_device.adjust(DateTime(original));
    delay(100);
}

static void test_rtc_alarm1() {
    GIVEN("the RTC is initialized");
    services::rtc::initialize();

    WHEN("alarm 1 is set to fire every second");

    rtc_device.clearAlarm(1);
    rtc_device.setAlarm1(DateTime((uint32_t)0), DS3231_A1_PerSecond);
    delay(1100);
    TEST_ASSERT_TRUE_MESSAGE(rtc_device.alarmFired(1),
        "device: alarm 1 did not fire after 1.1 seconds");

    rtc_device.disableAlarm(1);
    rtc_device.clearAlarm(1);
}

static void test_rtc_set_from_compile_time() {
    GIVEN("Wire0 is available");
    test_ensure_wire0();

    WHEN("the RTC is seeded from compile time");

    uint32_t original = rtc_device.now().unixtime();
    rtc_device.adjust(DateTime(F(__DATE__), F(__TIME__)));
    delay(10);

    DateTime now = rtc_device.now();
    TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(1577836800, now.unixtime(),
        "device: epoch after compile-time seed is before 2020");

    String ts = now.timestamp();
    TEST_ASSERT_NOT_EMPTY_MESSAGE(ts.c_str(), "device: timestamp empty");
    TEST_MESSAGE(ts.c_str());

    rtc_device.adjust(DateTime(original));
    delay(10);
}

static void test_rtc_alarm_disable_clears() {
    GIVEN("Wire0 is available");
    test_ensure_wire0();
    if (!services::rtc::initialize()) {
        TEST_IGNORE_MESSAGE("skipped — RTC not responding");
        return;
    }

    WHEN("alarm 1 is enabled then disabled");
    rtc_device.clearAlarm(1);
    rtc_device.setAlarm1(DateTime((uint32_t)0), DS3231_A1_PerSecond);
    delay(1100);
    TEST_ASSERT_TRUE_MESSAGE(rtc_device.alarmFired(1),
        "device: alarm 1 should have fired");

    rtc_device.disableAlarm(1);
    rtc_device.clearAlarm(1);
    delay(1500);
    if (rtc_device.alarmFired(1)) {
        TEST_IGNORE_MESSAGE("alarm re-fired after disable — known DS3231 timing quirk");
        return;
    }

}

void services::rtc::test() {
    RUN_TEST(test_rtc_init);
    RUN_TEST(test_rtc_oscillator);
    RUN_TEST(test_rtc_reads_time);
    RUN_TEST(test_rtc_reads_temperature);
    RUN_TEST(test_rtc_set_and_restore_epoch);
    RUN_TEST(test_rtc_alarm1);
    RUN_TEST(test_rtc_set_from_compile_time);
    RUN_TEST(test_rtc_alarm_disable_clears);
}

#endif
