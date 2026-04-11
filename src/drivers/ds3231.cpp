#include "ds3231.h"
#include "../config.h"

#include <Arduino.h>
#include <Wire.h>
#include <DS3231.h>

static DS3231 rtc;

// ─────────────────────────────────────────────────────────────────────────────
//  Core
// ─────────────────────────────────────────────────────────────────────────────

bool ds3231_init(void) {
  rtc.setClockMode(false);
  if (!rtc.oscillatorCheck()) {
    DateTime compile_time(__DATE__, __TIME__);
    rtc.setEpoch(compile_time.unixtime(), false);
    delay(10);
  }
  // Probe: read time and verify we got something plausible
  DateTime now = RTClib::now();
  return now.year() >= 2020 && now.year() <= 2099;
}

bool ds3231_oscillator_ok(void) {
  return rtc.oscillatorCheck();
}

uint32_t ds3231_unixtime(void) {
  return RTClib::now().unixtime();
}

float ds3231_temperature(void) {
  return rtc.getTemperature();
}

const char *ds3231_time_string(void) {
  static char buf[20];
  DateTime now = RTClib::now();
  snprintf(buf, sizeof(buf), "%04u-%02u-%02u %02u:%02u:%02u",
           now.year(), now.month(), now.day(),
           now.hour(), now.minute(), now.second());
  return buf;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Time setting
// ─────────────────────────────────────────────────────────────────────────────

void ds3231_set_epoch(uint32_t epoch) {
  rtc.setEpoch(epoch, false);
}

void ds3231_set_from_compile_time(void) {
  // DateTime(const char* date, const char* time) parses __DATE__ and __TIME__
  rtc.adjust(DateTime(__DATE__, __TIME__));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Alarms
//
//  When enabling one alarm, the other must be prevented from firing —
//  a stale flag on either alarm blocks the INT pin from going low.
//  See DS3231 docs: "How (and Why) to Prevent an Alarm Entirely"
// ─────────────────────────────────────────────────────────────────────────────

// NOTE: Do NOT use 0xFF in time fields — the DS3231 library passes them through
// decToBcd() which overflows and sets bit 7 (the alarm mask bit), accidentally
// re-arming the alarm instead of preventing it.
// Instead, use day=0 in date mode (alarmIsDay=false) — no month has day 0,
// so the alarm comparison can never match.

static void prevent_alarm2(void) {
  rtc.turnOffAlarm(2);
  rtc.setA2Time(0, 0, 0, 0b00000000, false, false, false);
  rtc.checkIfAlarm(2);
}

static void prevent_alarm1(void) {
  rtc.turnOffAlarm(1);
  rtc.setA1Time(0, 0, 0, 0, 0b00000000, false, false, false);
  rtc.checkIfAlarm(1);
}

void ds3231_alarm1_every_second(void) {
  rtc.turnOffAlarm(1);
  rtc.setA1Time(0, 0, 0, 0, 0b00001111, false, false, false);
  rtc.turnOnAlarm(1);
  rtc.checkIfAlarm(1);
  prevent_alarm2();
}

void ds3231_alarm1_at(uint8_t hour, uint8_t minute, uint8_t second) {
  rtc.turnOffAlarm(1);
  rtc.setA1Time(0, hour, minute, second, 0b00001000, false, false, false);
  rtc.turnOnAlarm(1);
  rtc.checkIfAlarm(1);
  prevent_alarm2();
}

void ds3231_alarm1_disable(void) {
  prevent_alarm1();
}

bool ds3231_alarm1_fired(void) {
  return rtc.checkIfAlarm(1);
}

void ds3231_alarm2_every_minute(void) {
  rtc.turnOffAlarm(2);
  rtc.setA2Time(0, 0, 0, 0b01100000, false, false, false);
  rtc.turnOnAlarm(2);
  rtc.checkIfAlarm(2);
  prevent_alarm1();
}

void ds3231_alarm2_at(uint8_t hour, uint8_t minute) {
  rtc.turnOffAlarm(2);
  rtc.setA2Time(0, hour, minute, 0b01000000, false, false, false);
  rtc.turnOnAlarm(2);
  rtc.checkIfAlarm(2);
  prevent_alarm1();
}

void ds3231_alarm2_disable(void) {
  prevent_alarm2();
}

bool ds3231_alarm2_fired(void) {
  return rtc.checkIfAlarm(2);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tests
//  describe("DS3231 RTC")
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING

#include "../testing/it.h"
#include "../testing/i2c_helpers.h"

static void ds3231_test_init(void) {
  test_ensure_wire0();
  TEST_MESSAGE("user asks the device to initialize the DS3231");
  TEST_ASSERT_TRUE_MESSAGE(ds3231_init(),
    "device: ds3231_init() failed");
  TEST_MESSAGE("DS3231 initialized in 24h mode");
}

static void ds3231_test_oscillator(void) {
  TEST_MESSAGE("user checks if the DS3231 oscillator is running");
  ds3231_init();
  TEST_ASSERT_TRUE_MESSAGE(ds3231_oscillator_ok(),
    "device: oscillator stopped — battery may be dead");
  TEST_MESSAGE("oscillator is running");
}

static void ds3231_test_reads_time(void) {
  TEST_MESSAGE("user reads the current time from the DS3231");
  ds3231_init();
  uint32_t epoch = ds3231_unixtime();
  // Epoch should be after 2020-01-01 (1577836800)
  TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(1577836800, epoch,
    "device: epoch is before 2020 — RTC may not be set");
  const char *time_str = ds3231_time_string();
  TEST_ASSERT_NOT_EMPTY_MESSAGE(time_str,
    "device: time string is empty");
  TEST_MESSAGE(time_str);
}

static void ds3231_test_reads_temperature(void) {
  TEST_MESSAGE("user reads temperature from the DS3231");
  ds3231_init();
  float temp = ds3231_temperature();
  // DS3231 operates -40 to +85C; sanity check
  TEST_ASSERT_FLOAT_WITHIN_MESSAGE(60.0f, 22.5f, temp,
    "device: temperature outside plausible range (-37.5 to 82.5)");
  char msg[32];
  snprintf(msg, sizeof(msg), "%.2f C", temp);
  TEST_MESSAGE(msg);
}

static void ds3231_test_set_and_restore_epoch(void) {
  TEST_MESSAGE("user sets epoch, verifies, then restores original time");
  ds3231_init();

  // Save current time
  uint32_t original_epoch = ds3231_unixtime();

  // Set to a known value: 2024-04-05 12:00:00 UTC = 1712318400
  uint32_t test_epoch = 1712318400;
  ds3231_set_epoch(test_epoch);
  delay(100);

  uint32_t readback = ds3231_unixtime();
  // Allow 2 seconds of drift
  TEST_ASSERT_UINT32_WITHIN_MESSAGE(2, test_epoch, readback,
    "device: epoch readback doesn't match what was set");

  // Restore original time
  ds3231_set_epoch(original_epoch);
  delay(100);

  TEST_MESSAGE("epoch set/read verified and original time restored");
}

static void ds3231_test_alarm1(void) {
  TEST_MESSAGE("user enables alarm 1 (every second) and checks if it fires");
  ds3231_init();

  ds3231_alarm1_every_second();
  delay(1100); // wait just over 1 second
  TEST_ASSERT_TRUE_MESSAGE(ds3231_alarm1_fired(),
    "device: alarm 1 did not fire after 1.1 seconds");

  ds3231_alarm1_disable();
  TEST_MESSAGE("alarm 1 fired and was disabled");
}

static void ds3231_test_set_from_compile_time(void) {
  TEST_MESSAGE("user seeds RTC from compile time and verifies plausible result");
  test_ensure_wire0();

  uint32_t original = ds3231_unixtime();
  ds3231_set_from_compile_time();
  delay(10);

  uint32_t epoch = ds3231_unixtime();
  TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(1577836800, epoch,
    "device: epoch after compile-time seed is before 2020");

  const char *time_str = ds3231_time_string();
  TEST_ASSERT_NOT_EMPTY_MESSAGE(time_str,
    "device: time string empty after compile-time seed");

  TEST_MESSAGE(time_str);

  // Restore original RTC time
  ds3231_set_epoch(original);
  delay(10);
}

static void ds3231_test_alarm_disable_clears(void) {
  TEST_MESSAGE("user enables alarm 1, disables it, and verifies it stops firing");
  test_ensure_wire0();
  ds3231_init();

  ds3231_alarm1_every_second();
  delay(1100);
  TEST_ASSERT_TRUE_MESSAGE(ds3231_alarm1_fired(),
    "device: alarm 1 should have fired");

  ds3231_alarm1_disable();
  delay(1100);
  TEST_ASSERT_FALSE_MESSAGE(ds3231_alarm1_fired(),
    "device: alarm 1 should not fire after disable");

  TEST_MESSAGE("alarm disable verified");
}

void ds3231_run_tests(void) {
  it("user observes that the DS3231 initializes",
     ds3231_test_init);
  it("user observes that the oscillator is running",
     ds3231_test_oscillator);
  it("user observes that the DS3231 reads a valid time",
     ds3231_test_reads_time);
  it("user observes that the DS3231 reads a plausible temperature",
     ds3231_test_reads_temperature);
  it("user observes that epoch can be set and restored cleanly",
     ds3231_test_set_and_restore_epoch);
  it("user observes that alarm 1 fires within 1 second",
     ds3231_test_alarm1);
  it("user observes that set_from_compile_time produces a valid time",
     ds3231_test_set_from_compile_time);
  it("user observes that disabling alarm 1 stops it from firing",
     ds3231_test_alarm_disable_clears);
}

#endif
