#pragma once

#ifdef PIO_UNIT_TESTING

#include <unity.h>
#include <string.h>
#include <config.h>
#include <Arduino.h>
#include <Wire.h>
#include <Preferences.h>
#include <i2c.h>

// ─────────────────────────────────────────────────────────────────────────────
//  BDD narration macros
//
//  These are thin wrappers over Unity's TEST_MESSAGE. The Python test runner
//  (tests/test_custom_runner.py) parses the [KEYWORD] prefix to produce
//  Ward-inspired BDD output with semantic colors and progressive indentation.
//
//  What we use from Unity:
//    TEST_MESSAGE / TEST_PRINTF    — narrative output (TEST_PRINTF for formatted)
//      CAVEAT: TEST_PRINTF does NOT support width/precision (%-16s, %.2f).
//      Those cause va_arg misalignment → ESP32 LoadProhibited crash.
//      Use snprintf + TEST_MESSAGE for format strings with modifiers.
//    TEST_ASSERT_EQUAL_STRING      — prefer over strcmp-based assertions
//    TEST_ASSERT_EQUAL_MEMORY      — prefer over memcmp for struct roundtrips
//    TEST_ASSERT_FLOAT_WITHIN      — prefer for sensor range checks
//    TEST_ASSERT_FLOAT_IS_DETERMINATE — add to sensor reads to catch NaN/Inf
//    TEST_ASSERT_NOT_EMPTY         — prefer for "is this string set?" checks
//    UNITY_INCLUDE_EXEC_TIME       — per-test timing (enabled in unity_config.h)
//    UNITY_INCLUDE_PRINT_FORMATTED — enables TEST_PRINTF (enabled in unity_config.h)
//
//  What we DON'T use, and why:
//    Unity Fixture (extras/fixture/)
//      TEST_GROUP / TEST / RUN_TEST_CASE — provides grouping + CLI filtering,
//      but (a) Fixture's name format "TEST(Group, Name)" breaks PlatformIO's
//      parse_test_case regex ([^\s]+ can't handle the space), (b) Fixture's
//      CLI filtering (-g, -n) requires argv which doesn't exist on ESP32
//      (Arduino's setup() has no argc/argv), (c) Fixture auto-includes
//      unity_memory.h which wraps stdlib malloc/free — wrong on ESP32 with
//      FreeRTOS (needs pvPortMalloc/vPortFree). Our MODULE() macro serves the
//      rendering purpose without any of these compatibility issues.
//
//    Unity auto/ scripts (generate_test_runner.rb, stylize_as_junit.py)
//      PlatformIO handles test wiring and already provides --junit-output-path
//      and --json-output-path built-in. Manual test() functions give us MODULE
//      grouping control that auto-generation would lose.
//
//    Unity BDD (extras/bdd/unity_bdd.h)
//      The upstream GIVEN/WHEN/THEN are if(0){printf}else — pure documentation
//      scaffolding that emits NO output. We need actual output for the Python
//      runner to parse, so our macros use TEST_MESSAGE instead.
// ─────────────────────────────────────────────────────────────────────────────

#define GIVEN(desc)  TEST_MESSAGE("[GIVEN] "  desc)
#define WHEN(desc)   TEST_MESSAGE("[WHEN] "   desc)
#define THEN(desc)   TEST_MESSAGE("[THEN] "   desc)
#define AND(desc)    TEST_MESSAGE("[AND] "    desc)
#define MODULE(name) TEST_MESSAGE("[MODULE] " name)

// ─────────────────────────────────────────────────────────────────────────────
//  I2C helpers
// ─────────────────────────────────────────────────────────────────────────────

static inline void test_ensure_wire0(void) {
  Wire.begin(config::i2c::BUS_0.sda_gpio, config::i2c::BUS_0.scl_gpio,
             config::i2c::FREQUENCY_KHZ * 1000);
  Wire.setTimeOut(100);
}

static inline void test_ensure_wire1(void) {
  Wire1.begin(config::i2c::BUS_1.sda_gpio, config::i2c::BUS_1.scl_gpio,
              config::i2c::FREQUENCY_KHZ * 1000);
  Wire1.setTimeOut(100);
}

static inline void test_ensure_wire1_with_power(void) {
  hardware::i2c::enable();
  test_ensure_wire1();
}

// ─────────────────────────────────────────────────────────────────────────────
//  NVS snapshot/restore helpers
// ─────────────────────────────────────────────────────────────────────────────

struct NvsStringSnapshot {
  char value[128];
  bool exists;
};

struct NvsBoolSnapshot {
  bool value;
  bool exists;
};

static inline void nvs_snapshot_string(Preferences &prefs, const char *key,
                                       NvsStringSnapshot *snap) {
  snap->exists = prefs.isKey(key);
  if (snap->exists) {
    prefs.getString(key, snap->value, sizeof(snap->value));
  } else {
    snap->value[0] = '\0';
  }
}

static inline void nvs_snapshot_bool(Preferences &prefs, const char *key,
                                     NvsBoolSnapshot *snap, bool default_val) {
  snap->exists = prefs.isKey(key);
  snap->value = prefs.getBool(key, default_val);
}

static inline void nvs_restore_string(Preferences &prefs, const char *key,
                                      const NvsStringSnapshot *snap) {
  if (snap->exists) prefs.putString(key, snap->value);
}

static inline void nvs_restore_bool(Preferences &prefs, const char *key,
                                    const NvsBoolSnapshot *snap) {
  if (snap->exists) prefs.putBool(key, snap->value);
}

struct WifiNvsSnapshot {
  NvsStringSnapshot sta_ssid;
  NvsStringSnapshot sta_pass;
  NvsStringSnapshot sta_identity;
  NvsStringSnapshot sta_username;
  NvsBoolSnapshot sta_enterprise;
  NvsStringSnapshot ap_ssid;
  NvsStringSnapshot ap_pass;
  NvsBoolSnapshot ap_on;
};

static inline void wifi_nvs_save(WifiNvsSnapshot *snap) {
  Preferences prefs;
  if (!prefs.begin(config::wifi::NVS_NAMESPACE, true)) return;
  nvs_snapshot_string(prefs, "sta_ssid", &snap->sta_ssid);
  nvs_snapshot_string(prefs, "sta_pass", &snap->sta_pass);
  nvs_snapshot_string(prefs, "sta_identity", &snap->sta_identity);
  nvs_snapshot_string(prefs, "sta_username", &snap->sta_username);
  nvs_snapshot_bool(prefs, "sta_enterprise", &snap->sta_enterprise, false);
  nvs_snapshot_string(prefs, "ap_ssid", &snap->ap_ssid);
  nvs_snapshot_string(prefs, "ap_pass", &snap->ap_pass);
  nvs_snapshot_bool(prefs, "ap_on", &snap->ap_on, true);
  prefs.end();
}

static inline void wifi_nvs_restore(const WifiNvsSnapshot *snap) {
  Preferences prefs;
  if (!prefs.begin(config::wifi::NVS_NAMESPACE, false)) return;
  prefs.clear();
  nvs_restore_string(prefs, "sta_ssid", &snap->sta_ssid);
  nvs_restore_string(prefs, "sta_pass", &snap->sta_pass);
  nvs_restore_string(prefs, "sta_identity", &snap->sta_identity);
  nvs_restore_string(prefs, "sta_username", &snap->sta_username);
  nvs_restore_bool(prefs, "sta_enterprise", &snap->sta_enterprise);
  nvs_restore_string(prefs, "ap_ssid", &snap->ap_ssid);
  nvs_restore_string(prefs, "ap_pass", &snap->ap_pass);
  nvs_restore_bool(prefs, "ap_on", &snap->ap_on);
  prefs.end();
}

#endif
