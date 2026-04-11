#ifdef PIO_UNIT_TESTING

#include "provisioning.h"
#include "wifi.h"
#include "../testing/it.h"
#include "../testing/nvs_helpers.h"
#include "../config.h"

#include <Preferences.h>

static void provisioning_test_detects_provisioned_with_credentials(void) {
  TEST_MESSAGE("user verifies provisioning detection");

#if defined(CONFIG_WIFI_SSID) && defined(CONFIG_WIFI_PASS)
  if (strlen(CONFIG_WIFI_SSID) > 0) {
    TEST_ASSERT_TRUE_MESSAGE(provisioning_is_provisioned(),
      "device: should be provisioned when build flags have SSID");
    TEST_MESSAGE("provisioned via build flags");
    return;
  }
#endif

  char ssid[33] = {0};
  if (wifi_get_ssid(ssid, sizeof(ssid)) && ssid[0] != '\0') {
    TEST_ASSERT_TRUE_MESSAGE(provisioning_is_provisioned(),
      "device: should be provisioned when NVS has SSID");
    TEST_MESSAGE("provisioned via NVS");
  } else {
    TEST_ASSERT_FALSE_MESSAGE(provisioning_is_provisioned(),
      "device: should not be provisioned when no credentials exist");
    TEST_MESSAGE("not provisioned — correct");
  }
}

static void provisioning_test_custom_config_roundtrip(void) {
  TEST_MESSAGE("user stores and retrieves custom provisioning config");

#if !CONFIG_PROV_ENABLED
  TEST_IGNORE_MESSAGE("CONFIG_PROV_ENABLED=0 — getters are stubs");
#endif

  Preferences prefs;
  prefs.begin(CONFIG_PROV_NVS_NAMESPACE, false);
  prefs.putString("username", "testuser");
  prefs.putString("device_name", "test-sensor-1");
  prefs.putString("api_key", "sk-test-12345");
  prefs.end();

  char buf[64];

  TEST_ASSERT_TRUE_MESSAGE(provisioning_get_username(buf, sizeof(buf)),
    "device: username should be retrievable after write");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("testuser", buf,
    "device: username value mismatch");

  TEST_ASSERT_TRUE_MESSAGE(provisioning_get_device_name(buf, sizeof(buf)),
    "device: device_name should be retrievable after write");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("test-sensor-1", buf,
    "device: device_name value mismatch");

  TEST_ASSERT_TRUE_MESSAGE(provisioning_get_api_key(buf, sizeof(buf)),
    "device: api_key should be retrievable after write");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("sk-test-12345", buf,
    "device: api_key value mismatch");

  prefs.begin(CONFIG_PROV_NVS_NAMESPACE, false);
  prefs.clear();
  prefs.end();

  TEST_ASSERT_FALSE_MESSAGE(provisioning_get_username(buf, sizeof(buf)),
    "device: username should be gone after cleanup");
  TEST_MESSAGE("custom config roundtrip passed");
}

static void provisioning_test_reset_clears_all(void) {
  TEST_MESSAGE("user resets provisioning and verifies config is cleared");

#if !CONFIG_PROV_ENABLED
  TEST_IGNORE_MESSAGE("CONFIG_PROV_ENABLED=0 — reset is a no-op");
#endif

  WifiNvsSnapshot wifi_snap;
  wifi_nvs_save(&wifi_snap);

  Preferences prefs;
  prefs.begin(CONFIG_PROV_NVS_NAMESPACE, false);
  prefs.putString("username", "will-be-cleared");
  prefs.end();

  char buf[64];
  TEST_ASSERT_TRUE_MESSAGE(provisioning_get_username(buf, sizeof(buf)),
    "device: username should exist before reset");

  provisioning_reset();

  TEST_ASSERT_FALSE_MESSAGE(provisioning_get_username(buf, sizeof(buf)),
    "device: username should be gone after provisioning_reset");

  wifi_nvs_restore(&wifi_snap);
  TEST_MESSAGE("provisioning reset cleared config, WiFi NVS restored");
}

static void provisioning_test_empty_config_returns_false(void) {
  TEST_MESSAGE("user reads config from empty NVS namespace");

  Preferences prefs;
  prefs.begin(CONFIG_PROV_NVS_NAMESPACE, false);
  prefs.clear();
  prefs.end();

  char buf[64];
  TEST_ASSERT_FALSE_MESSAGE(provisioning_get_username(buf, sizeof(buf)),
    "device: should return false when no username stored");
  TEST_ASSERT_FALSE_MESSAGE(provisioning_get_api_key(buf, sizeof(buf)),
    "device: should return false when no api_key stored");
  TEST_ASSERT_FALSE_MESSAGE(provisioning_get_device_name(buf, sizeof(buf)),
    "device: should return false when no device_name stored");
  TEST_MESSAGE("all getters return false on empty NVS");
}

static void provisioning_test_service_uuids_configured(void) {
  TEST_MESSAGE("user verifies provisioning BLE UUIDs are configured");

  TEST_ASSERT_NOT_EMPTY_MESSAGE(CONFIG_PROV_SERVICE_UUID,
    "device: provisioning service UUID must not be empty");
  TEST_ASSERT_NOT_EMPTY_MESSAGE(CONFIG_PROV_CONFIG_UUID,
    "device: provisioning config UUID must not be empty");
  TEST_ASSERT_NOT_EMPTY_MESSAGE(CONFIG_PROV_POP,
    "device: proof of possession must not be empty");
  TEST_ASSERT_NOT_EMPTY_MESSAGE(CONFIG_PROV_NVS_NAMESPACE,
    "device: provisioning NVS namespace must not be empty");
  TEST_MESSAGE("all provisioning UUIDs and config are set");
}

void provisioning_run_tests(void) {
  it("user observes provisioning state detection works",
     provisioning_test_detects_provisioned_with_credentials);
  it("user stores and retrieves custom config via NVS",
     provisioning_test_custom_config_roundtrip);
  it("user resets provisioning and verifies cleanup",
     provisioning_test_reset_clears_all);
  it("user reads config from empty NVS and gets false",
     provisioning_test_empty_config_returns_false);
  it("user verifies BLE provisioning UUIDs are configured",
     provisioning_test_service_uuids_configured);
}

#endif
