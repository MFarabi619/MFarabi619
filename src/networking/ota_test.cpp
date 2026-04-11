#ifdef PIO_UNIT_TESTING

#include "ota.h"
#include "../testing/it.h"

#include <Arduino.h>

static void ota_test_config(void) {
  TEST_MESSAGE("user verifies OTA configuration");

  TEST_ASSERT_GREATER_THAN_UINT16_MESSAGE(0, CONFIG_OTA_PORT,
    "device: OTA port must be > 0");

#if CONFIG_OTA_ENABLED
  char msg[64];
  snprintf(msg, sizeof(msg), "OTA enabled on port %d", CONFIG_OTA_PORT);
  TEST_MESSAGE(msg);
#else
  TEST_MESSAGE("OTA is disabled (CONFIG_OTA_ENABLED=0)");
#endif
}

static void ota_test_noop_when_disabled(void) {
  TEST_MESSAGE("user verifies OTA service is safe to call when disabled");

#if !CONFIG_OTA_ENABLED
  ota_start();
  ota_service();
  TEST_MESSAGE("ota_start() and ota_service() are no-ops when disabled");
#else
  TEST_IGNORE_MESSAGE("OTA is enabled — skip no-op test");
#endif
}

void ota_run_tests(void) {
  it("user observes that OTA config is valid",
     ota_test_config);
  it("user observes that OTA is safe to call when disabled",
     ota_test_noop_when_disabled);
}

#endif
