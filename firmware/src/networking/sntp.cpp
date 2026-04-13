#include "sntp.h"
#include "../services/rtc.h"

#include <Arduino.h>
#include <time.h>
#include "esp_sntp.h"

static volatile bool synced = false;
static volatile uint32_t synced_epoch = 0;

static void on_time_sync(struct timeval *tv) {
  (void)tv;
  time_t now_utc;
  time(&now_utc);
  synced_epoch = (uint32_t)now_utc;
  synced = true;
  Serial.printf("[ntp] synced, epoch=%lu\n", (unsigned long)now_utc);
}

bool networking::sntp::sync() {
  synced = false;
  synced_epoch = 0;

  setenv("TZ", config::sntp::TIME_ZONE, 1);
  tzset();

  sntp_set_time_sync_notification_cb(on_time_sync);
  configTzTime(config::sntp::TIME_ZONE, config::sntp::SERVER_1, config::sntp::SERVER_2);

  uint32_t start = millis();
  while (!synced && (millis() - start) < config::sntp::SYNC_TIMEOUT_MS) {
    vTaskDelay(pdMS_TO_TICKS(100));
  }

  if (synced && synced_epoch > 0) {
    services::rtc::setEpoch(synced_epoch);
    Serial.printf("[ntp] local time: %s\n", networking::sntp::accessLocalTimeString());
  } else {
    Serial.println(F("[ntp] sync timeout — using RTC time"));
  }

  return synced;
}

bool networking::sntp::isSynced() {
  return synced;
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
#include "wifi.h"
#include "../services/rtc.h"
#include "../testing/it.h"
#include "../testing/nvs_helpers.h"

namespace networking::sntp { void test(void); }

static WifiNvsSnapshot saved;
static void save_nvs(void) { wifi_nvs_save(&saved); }
static void restore_nvs(void) { wifi_nvs_restore(&saved); }

static void sntp_test_config_defaults(void) {
  TEST_MESSAGE("user verifies NTP configuration");

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

  TEST_MESSAGE("NTP configuration is valid");
}

static void sntp_test_not_synced_before_connect(void) {
  TEST_MESSAGE("user checks NTP status before WiFi");

  TEST_ASSERT_FALSE_MESSAGE(networking::sntp::isSynced(),
    "device: NTP should not be synced before wifi_connect");

  TEST_MESSAGE("NTP is not synced before WiFi");
}

static void sntp_test_syncs_and_updates_rtc(void) {
  TEST_MESSAGE("user connects WiFi, syncs NTP, and verifies RTC is updated");

  save_nvs();

  networking::wifi::sta::initialize();
  if (!networking::wifi::sta::connect()) {
    restore_nvs();
    TEST_IGNORE_MESSAGE("skipped — no WiFi connection");
    return;
  }

  TEST_MESSAGE("WiFi connected, starting NTP sync...");
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

  TEST_MESSAGE("NTP synced and RTC updated to UTC");

  restore_nvs();
}

void networking::sntp::test(void) {
  it("user observes that NTP configuration is valid",
     sntp_test_config_defaults);
  it("user observes that NTP is not synced before WiFi",
     sntp_test_not_synced_before_connect);
  it("user observes that NTP syncs and updates the RTC",
     sntp_test_syncs_and_updates_rtc);
}

#endif
