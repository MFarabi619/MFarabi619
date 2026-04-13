#include "sleep.h"

#include "../config.h"
#include "../hardware/i2c.h"
#include "../services/data_logger.h"

#include <Arduino.h>
#include <Preferences.h>
#include <WiFi.h>
#include <esp_sleep.h>

namespace {

bool sleep_pending = false;
uint32_t requested_duration_seconds = 0;
uint32_t request_time_ms = 0;
bool timer_wakeup_enabled = false;
uint64_t timer_wakeup_us = 0;
const char *wake_cause_string = "power_on";
SleepConfig persisted_config = {
  .enabled = config::sleep::DEFAULT_ENABLED,
  .duration_seconds = config::sleep::DEFAULT_DURATION_SECONDS,
};

bool open_preferences(bool readonly, Preferences *prefs) {
  return prefs && prefs->begin(config::sleep::NVS_NAMESPACE, readonly);
}

const char *translate_wake_cause(esp_sleep_wakeup_cause_t cause) {
  switch (cause) {
    case ESP_SLEEP_WAKEUP_EXT0: return "ext0";
    case ESP_SLEEP_WAKEUP_EXT1: return "ext1";
    case ESP_SLEEP_WAKEUP_TIMER: return "timer";
    case ESP_SLEEP_WAKEUP_TOUCHPAD: return "touchpad";
    case ESP_SLEEP_WAKEUP_ULP: return "ulp";
    case ESP_SLEEP_WAKEUP_GPIO: return "gpio";
    case ESP_SLEEP_WAKEUP_UART: return "uart";
    case ESP_SLEEP_WAKEUP_WIFI: return "wifi";
    case ESP_SLEEP_WAKEUP_COCPU: return "cocpu";
    case ESP_SLEEP_WAKEUP_COCPU_TRAP_TRIG: return "cocpu_trap";
    case ESP_SLEEP_WAKEUP_BT: return "bluetooth";
    case ESP_SLEEP_WAKEUP_UNDEFINED:
    default: return "power_on";
  }
}

bool validate_config(const SleepConfig *sleep_config) {
  return sleep_config && sleep_config->duration_seconds > 0;
}

void load_config() {
  persisted_config.enabled = config::sleep::DEFAULT_ENABLED;
  persisted_config.duration_seconds = config::sleep::DEFAULT_DURATION_SECONDS;

  Preferences prefs;
  if (!open_preferences(true, &prefs)) return;
  persisted_config.enabled = prefs.getBool(config::sleep::ENABLED_KEY,
                                           config::sleep::DEFAULT_ENABLED);
  persisted_config.duration_seconds = prefs.getUInt(
      config::sleep::DURATION_KEY, config::sleep::DEFAULT_DURATION_SECONDS);
  prefs.end();

  if (persisted_config.duration_seconds == 0) {
    persisted_config.duration_seconds = config::sleep::DEFAULT_DURATION_SECONDS;
  }
}

void enter_sleep_now() {
  timer_wakeup_us = static_cast<uint64_t>(requested_duration_seconds) * 1000000ULL;
  timer_wakeup_enabled = true;
  esp_sleep_disable_wakeup_source(ESP_SLEEP_WAKEUP_ALL);
  esp_sleep_enable_timer_wakeup(timer_wakeup_us);

  Serial.printf("[sleep] entering deep sleep for %lu second(s)\n",
                static_cast<unsigned long>(requested_duration_seconds));
  services::data_logger::flushNow();
  Serial.flush();

  WiFi.mode(WIFI_OFF);
  hardware::i2c::disable();
  delay(50);

  esp_deep_sleep_start();
}

}

void power::sleep::initialize() {
  sleep_pending = false;
  requested_duration_seconds = 0;
  request_time_ms = 0;
  timer_wakeup_enabled = false;
  timer_wakeup_us = 0;
  load_config();
  wake_cause_string = translate_wake_cause(esp_sleep_get_wakeup_cause());
}

bool power::sleep::request(SleepCommand *command) {
  if (!command) return false;
  command->ok = false;

  if (command->duration_seconds == 0) {
    return false;
  }

  requested_duration_seconds = command->duration_seconds;
  request_time_ms = millis();
  sleep_pending = true;
  command->ok = true;
  return true;
}

bool power::sleep::requestConfigured(SleepCommand *command) {
  if (!command) return false;
  command->ok = false;

  if (!persisted_config.enabled || persisted_config.duration_seconds == 0) {
    return false;
  }

  command->duration_seconds = persisted_config.duration_seconds;
  return power::sleep::request(command);
}

void power::sleep::service() {
  if (!sleep_pending) return;
  if (millis() - request_time_ms < 100) return;
  sleep_pending = false;
  enter_sleep_now();
}

void power::sleep::abortPending() {
  sleep_pending = false;
  requested_duration_seconds = 0;
  request_time_ms = 0;
  timer_wakeup_enabled = false;
  timer_wakeup_us = 0;
}

const char *power::sleep::accessWakeCause() {
  return wake_cause_string;
}

bool power::sleep::accessStatus(SleepStatusSnapshot *snapshot) {
  if (!snapshot) return false;
  snapshot->pending = sleep_pending;
  snapshot->requested_duration_seconds = requested_duration_seconds;
  snapshot->wake_cause = wake_cause_string;
  snapshot->timer_wakeup_enabled = timer_wakeup_enabled;
  snapshot->timer_wakeup_us = timer_wakeup_us;
  snapshot->config_enabled = persisted_config.enabled;
  snapshot->default_duration_seconds = persisted_config.duration_seconds;
  return true;
}

bool power::sleep::accessConfig(SleepConfig *config) {
  if (!config) return false;
  *config = persisted_config;
  return true;
}

bool power::sleep::storeConfig(const SleepConfig *sleep_config) {
  if (!validate_config(sleep_config)) return false;

  Preferences prefs;
  if (!open_preferences(false, &prefs)) return false;
  prefs.putBool(config::sleep::ENABLED_KEY, sleep_config->enabled);
  prefs.putUInt(config::sleep::DURATION_KEY, sleep_config->duration_seconds);
  prefs.end();

  persisted_config = *sleep_config;
  return true;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING

#include "../testing/it.h"

namespace power::sleep { void test(void); }

namespace {

struct SleepNvsSnapshot {
  bool enabled_exists;
  bool enabled;
  bool duration_exists;
  uint32_t duration_seconds;
};

void sleep_nvs_save(SleepNvsSnapshot *snapshot) {
  if (!snapshot) return;
  memset(snapshot, 0, sizeof(*snapshot));

  Preferences prefs;
  if (!open_preferences(true, &prefs)) return;
  snapshot->enabled_exists = prefs.isKey(config::sleep::ENABLED_KEY);
  snapshot->enabled = prefs.getBool(config::sleep::ENABLED_KEY,
                                    config::sleep::DEFAULT_ENABLED);
  snapshot->duration_exists = prefs.isKey(config::sleep::DURATION_KEY);
  snapshot->duration_seconds = prefs.getUInt(config::sleep::DURATION_KEY,
                                             config::sleep::DEFAULT_DURATION_SECONDS);
  prefs.end();
}

void sleep_nvs_restore(const SleepNvsSnapshot *snapshot) {
  if (!snapshot) return;

  Preferences prefs;
  if (!open_preferences(false, &prefs)) return;
  prefs.clear();
  if (snapshot->enabled_exists)
    prefs.putBool(config::sleep::ENABLED_KEY, snapshot->enabled);
  if (snapshot->duration_exists)
    prefs.putUInt(config::sleep::DURATION_KEY, snapshot->duration_seconds);
  prefs.end();

  power::sleep::initialize();
  power::sleep::abortPending();
}

static SleepNvsSnapshot saved_sleep_nvs = {};

void save_sleep_nvs() { sleep_nvs_save(&saved_sleep_nvs); }
void restore_sleep_nvs() { sleep_nvs_restore(&saved_sleep_nvs); }

static void sleep_test_default_config(void) {
  TEST_MESSAGE("user reads sleep config from empty NVS and gets defaults");

  save_sleep_nvs();
  Preferences prefs;
  TEST_ASSERT_TRUE_MESSAGE(open_preferences(false, &prefs),
    "device: sleep NVS namespace must be writable");
  prefs.clear();
  prefs.end();

  power::sleep::initialize();

  SleepConfig sleep_config = {};
  TEST_ASSERT_TRUE_MESSAGE(power::sleep::accessConfig(&sleep_config),
    "device: sleep config must be readable");
  TEST_ASSERT_EQUAL_MESSAGE(config::sleep::DEFAULT_ENABLED, sleep_config.enabled,
    "device: sleep enabled default mismatch");
  TEST_ASSERT_EQUAL_UINT32_MESSAGE(config::sleep::DEFAULT_DURATION_SECONDS,
    sleep_config.duration_seconds,
    "device: sleep duration default mismatch");

  restore_sleep_nvs();
  TEST_MESSAGE("default sleep config verified, NVS restored");
}

static void sleep_test_persist_config(void) {
  TEST_MESSAGE("user stores and retrieves deep sleep config via NVS");

  save_sleep_nvs();

  SleepConfig sleep_config = {
    .enabled = true,
    .duration_seconds = 42,
  };
  TEST_ASSERT_TRUE_MESSAGE(power::sleep::storeConfig(&sleep_config),
    "device: sleep config must persist");

  SleepConfig stored = {};
  TEST_ASSERT_TRUE_MESSAGE(power::sleep::accessConfig(&stored),
    "device: stored sleep config must be readable");
  TEST_ASSERT_TRUE_MESSAGE(stored.enabled,
    "device: persisted sleep enabled should be true");
  TEST_ASSERT_EQUAL_UINT32_MESSAGE(42, stored.duration_seconds,
    "device: persisted sleep duration mismatch");

  Preferences prefs;
  TEST_ASSERT_TRUE_MESSAGE(open_preferences(true, &prefs),
    "device: sleep NVS namespace must be readable");
  TEST_ASSERT_TRUE_MESSAGE(prefs.getBool(config::sleep::ENABLED_KEY, false),
    "device: sleep enabled flag not written to NVS");
  TEST_ASSERT_EQUAL_UINT32_MESSAGE(42,
    prefs.getUInt(config::sleep::DURATION_KEY, 0),
    "device: sleep duration not written to NVS");
  prefs.end();

  restore_sleep_nvs();
  TEST_MESSAGE("sleep config roundtrip verified, NVS restored");
}

static void sleep_test_rejects_invalid_duration(void) {
  TEST_MESSAGE("user tries to save an invalid sleep duration");

  SleepConfig sleep_config = {
    .enabled = true,
    .duration_seconds = 0,
  };
  TEST_ASSERT_FALSE_MESSAGE(power::sleep::storeConfig(&sleep_config),
    "device: zero-second sleep duration must be rejected");

  SleepCommand command = {
    .duration_seconds = 0,
    .ok = false,
  };
  TEST_ASSERT_FALSE_MESSAGE(power::sleep::request(&command),
    "device: zero-second one-shot sleep request must be rejected");
  TEST_MESSAGE("invalid sleep duration rejected");
}

static void sleep_test_status_reports_config(void) {
  TEST_MESSAGE("user reads sleep status and sees persisted config");

  save_sleep_nvs();

  SleepConfig sleep_config = {
    .enabled = true,
    .duration_seconds = 15,
  };
  TEST_ASSERT_TRUE(power::sleep::storeConfig(&sleep_config));

  SleepStatusSnapshot snapshot = {};
  TEST_ASSERT_TRUE_MESSAGE(power::sleep::accessStatus(&snapshot),
    "device: sleep status must be readable");
  TEST_ASSERT_TRUE_MESSAGE(snapshot.config_enabled,
    "device: status should report enabled sleep config");
  TEST_ASSERT_EQUAL_UINT32_MESSAGE(15, snapshot.default_duration_seconds,
    "device: status should report default sleep duration");

  SleepCommand command = {};
  TEST_ASSERT_TRUE_MESSAGE(power::sleep::requestConfigured(&command),
    "device: configured sleep request should succeed when enabled");
  TEST_ASSERT_EQUAL_UINT32_MESSAGE(15, command.duration_seconds,
    "device: configured sleep request should use persisted duration");

  power::sleep::abortPending();
  restore_sleep_nvs();
  TEST_MESSAGE("sleep status config snapshot verified, NVS restored");
}

}

void power::sleep::test(void) {
  it("user reads sleep config defaults from empty NVS",
     sleep_test_default_config);
  it("user stores and retrieves deep sleep config via NVS",
     sleep_test_persist_config);
  it("user observes invalid sleep duration is rejected",
     sleep_test_rejects_invalid_duration);
  it("user observes sleep status includes persisted config",
     sleep_test_status_reports_config);
}

#endif
