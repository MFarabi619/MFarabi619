#include "sntp.h"
#include "../services/rtc.h"

#include <atomic>
#include <Arduino.h>
#include <time.h>
#include "esp_sntp.h"

static std::atomic<bool> synced = false;
static std::atomic<uint32_t> synced_epoch = 0;

static void on_time_sync(struct timeval *tv) {
  (void)tv;
  time_t now_utc;
  time(&now_utc);
  synced_epoch.store((uint32_t)now_utc, std::memory_order_release);
  synced.store(true, std::memory_order_release);
  Serial.printf("[ntp] synced, epoch=%lu\n", (unsigned long)now_utc);
}

bool networking::sntp::sync() {
  synced.store(false, std::memory_order_relaxed);
  synced_epoch.store(0, std::memory_order_relaxed);

  setenv("TZ", config::sntp::TIME_ZONE, 1);
  tzset();

  sntp_set_time_sync_notification_cb(on_time_sync);
  configTzTime(config::sntp::TIME_ZONE, config::sntp::SERVER_1, config::sntp::SERVER_2);

  uint32_t start = millis();
  while (!synced.load(std::memory_order_acquire) && (millis() - start) < config::sntp::SYNC_TIMEOUT_MS) {
    vTaskDelay(pdMS_TO_TICKS(100));
  }

  uint32_t synced_epoch_value = synced_epoch.load(std::memory_order_acquire);
  if (synced.load(std::memory_order_acquire) && synced_epoch_value > 0) {
    services::rtc::setEpoch(synced_epoch_value);
    Serial.printf("[ntp] local time: %s\n", networking::sntp::accessLocalTimeString());
  } else {
    Serial.println(F("[ntp] sync timeout — using RTC time"));
  }

  return synced;
}

bool networking::sntp::isSynced() {
  return synced.load(std::memory_order_acquire);
}

const char *networking::sntp::accessLocalTimeString() {
  static char buf[32];
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo, 0)) {
    snprintf(buf, sizeof(buf), "(no time)");
    return buf;
  }
  strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S %Z", &timeinfo);
  return buf;
}

uint32_t networking::sntp::accessUTCEpoch() {
  time_t now_utc;
  time(&now_utc);
  return (uint32_t)now_utc;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING


#include "sntp.h"
#include <networking/wifi.h>
#include "services/rtc.h"
#include <testing/utils.h>


namespace networking::sntp { void test(void); }

static WifiNvsSnapshot saved;
static void save_nvs(void) { wifi_nvs_save(&saved); }
static void restore_nvs(void) { wifi_nvs_restore(&saved); }

static void test_sntp_config_defaults(void) {
  GIVEN("the NTP configuration");
  THEN("all required fields are set");

  TEST_ASSERT_NOT_NULL_MESSAGE(config::sntp::SERVER_1,
    "device: NTP server must not be NULL");
  TEST_ASSERT_NOT_EMPTY_MESSAGE(config::sntp::SERVER_1,
    "device: NTP server must not be empty");
  TEST_ASSERT_NOT_NULL_MESSAGE(config::sntp::TIME_ZONE,
    "device: timezone must not be NULL");
  TEST_ASSERT_NOT_EMPTY_MESSAGE(config::sntp::TIME_ZONE,
    "device: timezone must not be empty");
  TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(0, config::sntp::SYNC_TIMEOUT_MS,
    "device: sync timeout must be > 0");

}

static void test_sntp_not_synced_before_connect(void) {
  GIVEN("WiFi has not connected yet");
  THEN("NTP reports not synced");

  TEST_ASSERT_FALSE_MESSAGE(networking::sntp::isSynced(),
    "device: NTP should not be synced before wifi_connect");

}

static void test_sntp_syncs_and_updates_rtc(void) {
  GIVEN("WiFi is connected");
  WHEN("NTP sync completes");
  THEN("the RTC is updated to match");

  save_nvs();

  networking::wifi::sta::initialize();
  if (!networking::wifi::sta::connect()) {
    restore_nvs();
    TEST_IGNORE_MESSAGE("skipped — no WiFi connection");
    return;
  }

  services::rtc::initialize();
  uint32_t rtc_before = services::rtc::accessEpoch();

  bool synced = networking::sntp::sync();
  if (!synced) {
    restore_nvs();
    TEST_IGNORE_MESSAGE("skipped — NTP sync timed out");
    return;
  }

  TEST_MESSAGE(networking::sntp::accessLocalTimeString());

  uint32_t rtc_after = services::rtc::accessEpoch();
  uint32_t ntp_epoch = networking::sntp::accessUTCEpoch();

  TEST_ASSERT_UINT32_WITHIN_MESSAGE(2, ntp_epoch, rtc_after,
    "device: RTC epoch diverges from NTP by more than 2 seconds");

  uint32_t drift_before = (rtc_before > ntp_epoch) ? rtc_before - ntp_epoch : ntp_epoch - rtc_before;
  uint32_t drift_after  = (rtc_after > ntp_epoch)  ? rtc_after - ntp_epoch  : ntp_epoch - rtc_after;
  TEST_ASSERT_LESS_OR_EQUAL_UINT32_MESSAGE(drift_before, drift_after,
    "device: RTC did not get closer to NTP after sync — ds3231_set_epoch may not have been called");

  TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(1735689600, ntp_epoch,
    "device: NTP epoch is before 2025 — sync may have failed");

  restore_nvs();
}

void networking::sntp::test(void) {
  MODULE("NTP");
  RUN_TEST(test_sntp_config_defaults);
  RUN_TEST(test_sntp_not_synced_before_connect);
  RUN_TEST(test_sntp_syncs_and_updates_rtc);
}

#endif
