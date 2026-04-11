#ifdef PIO_UNIT_TESTING

#include "update.h"
#include "../testing/it.h"

#include <Arduino.h>
#include <SD.h>

static void update_test_sd_path_config(void) {
  TEST_MESSAGE("user verifies SD update path is configured");
  TEST_ASSERT_NOT_NULL(CONFIG_OTA_SD_PATH);
  TEST_ASSERT_TRUE_MESSAGE(strlen(CONFIG_OTA_SD_PATH) > 0,
    "device: CONFIG_OTA_SD_PATH must not be empty");

  char msg[80];
  snprintf(msg, sizeof(msg), "SD update file: %s", CONFIG_OTA_SD_PATH);
  TEST_MESSAGE(msg);
}

static void update_test_no_update_file(void) {
  TEST_MESSAGE("user verifies update_from_sd returns false when no file");

  if (!SD.begin(CONFIG_SD_CS_GPIO)) {
    TEST_IGNORE_MESSAGE("skipped — no SD card");
    return;
  }

  if (SD.exists(CONFIG_OTA_SD_PATH)) {
    TEST_IGNORE_MESSAGE("skipped — update.bin exists on SD (would flash!)");
    return;
  }

  TEST_ASSERT_FALSE_MESSAGE(update_from_sd(),
    "device: should return false when no update file");
  TEST_MESSAGE("correctly returns false with no update file");
}

static void update_test_rollback_status(void) {
  TEST_MESSAGE("user checks rollback availability");

  bool can = update_can_rollback();
  char msg[64];
  snprintf(msg, sizeof(msg), "rollback available: %s", can ? "yes" : "no");
  TEST_MESSAGE(msg);
}

void update_run_tests(void) {
  it("user observes that SD update path is configured",
     update_test_sd_path_config);
  it("user observes that update_from_sd handles missing file",
     update_test_no_update_file);
  it("user observes rollback availability",
     update_test_rollback_status);
}

#endif
