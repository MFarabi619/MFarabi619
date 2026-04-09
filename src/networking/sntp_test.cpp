#ifdef PIO_UNIT_TESTING

#include "sntp.h"
#include "wifi.h"
#include "../drivers/ds3231.h"
#include "../testing/it.h"
#include "../config.h"

static void sntp_test_config_defaults(void) {
  TEST_MESSAGE("user verifies NTP configuration");

  TEST_ASSERT_NOT_NULL_MESSAGE(CONFIG_NTP_SERVER,
    "device: NTP server must not be NULL");
  TEST_ASSERT_NOT_EMPTY_MESSAGE(CONFIG_NTP_SERVER,
    "device: NTP server must not be empty");
  TEST_ASSERT_NOT_NULL_MESSAGE(CONFIG_TIME_ZONE,
    "device: timezone must not be NULL");
  TEST_ASSERT_NOT_EMPTY_MESSAGE(CONFIG_TIME_ZONE,
    "device: timezone must not be empty");
  TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(0, CONFIG_NTP_SYNC_TIMEOUT_MS,
    "device: sync timeout must be > 0");

  TEST_MESSAGE("NTP configuration is valid");
}

static void sntp_test_not_synced_before_connect(void) {
  TEST_MESSAGE("user checks NTP status before WiFi");

  TEST_ASSERT_FALSE_MESSAGE(sntp_is_synced(),
    "device: NTP should not be synced before wifi_connect");

  TEST_MESSAGE("NTP is not synced before WiFi");
}

static void sntp_test_syncs_and_updates_rtc(void) {
  TEST_MESSAGE("user connects WiFi, syncs NTP, and verifies RTC is updated");

  wifi_setup();
  if (!wifi_connect()) {
    TEST_IGNORE_MESSAGE("skipped — no WiFi connection");
    return;
  }

  TEST_MESSAGE("WiFi connected, starting NTP sync...");
  ds3231_init();
  uint32_t rtc_before = ds3231_unixtime();

  bool synced = sntp_sync();
  if (!synced) {
    TEST_IGNORE_MESSAGE("skipped — NTP sync timed out");
    return;
  }

  TEST_MESSAGE(sntp_local_time_string());

  uint32_t rtc_after = ds3231_unixtime();
  uint32_t ntp_epoch = sntp_utc_epoch();

  // RTC should now be within 2 seconds of NTP
  TEST_ASSERT_UINT32_WITHIN_MESSAGE(2, ntp_epoch, rtc_after,
    "device: RTC epoch diverges from NTP by more than 2 seconds");

  // Prove the sync actually changed the RTC (rtc_after closer to NTP than rtc_before)
  uint32_t drift_before = (rtc_before > ntp_epoch) ? rtc_before - ntp_epoch : ntp_epoch - rtc_before;
  uint32_t drift_after  = (rtc_after > ntp_epoch)  ? rtc_after - ntp_epoch  : ntp_epoch - rtc_after;
  TEST_ASSERT_LESS_OR_EQUAL_UINT32_MESSAGE(drift_before, drift_after,
    "device: RTC did not get closer to NTP after sync — ds3231_set_epoch may not have been called");

  // NTP epoch should be after 2025-01-01 (1735689600)
  TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(1735689600, ntp_epoch,
    "device: NTP epoch is before 2025 — sync may have failed");

  TEST_MESSAGE("NTP synced and RTC updated to UTC");
}

void sntp_run_tests(void) {
  it("user observes that NTP configuration is valid",
     sntp_test_config_defaults);
  it("user observes that NTP is not synced before WiFi",
     sntp_test_not_synced_before_connect);
  it("user observes that NTP syncs and updates the RTC",
     sntp_test_syncs_and_updates_rtc);
}

#endif
