#ifdef PIO_UNIT_TESTING

#include "wifi.h"
#include "../testing/it.h"
#include "../testing/nvs_helpers.h"

#include <Arduino.h>

static WifiNvsSnapshot saved;
static void save_nvs(void) { wifi_nvs_save(&saved); }
static void restore_nvs(void) { wifi_nvs_restore(&saved); }

static void wifi_test_credentials_roundtrip(void) {
  save_nvs();

  wifi_set_credentials("test_ssid", "test_pass");

  char ssid[CONFIG_WIFI_SSID_IEEE_802_11_MAX_LENGTH + 1] = {0};
  char pass[CONFIG_WIFI_PASS_IEEE_802_11_MAX_LENGTH + 1] = {0};

  TEST_ASSERT_TRUE_MESSAGE(wifi_get_ssid(ssid, sizeof(ssid)),
    "device: wifi_get_ssid returned false");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("test_ssid", ssid,
    "device: SSID mismatch after roundtrip");

  TEST_ASSERT_TRUE_MESSAGE(wifi_get_password(pass, sizeof(pass)),
    "device: wifi_get_password returned false");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("test_pass", pass,
    "device: password mismatch after roundtrip");

  restore_nvs();
  TEST_MESSAGE("credentials roundtrip verified, NVS restored");
}

static void wifi_test_empty_nvs_returns_false(void) {
  save_nvs();

  Preferences preferences;
  preferences.begin(CONFIG_WIFI_NVS_NAMESPACE, false);
  preferences.remove("ssid");
  preferences.remove("pass");
  preferences.end();

  char ssid[CONFIG_WIFI_SSID_IEEE_802_11_MAX_LENGTH + 1] = {0};
  char pass[CONFIG_WIFI_PASS_IEEE_802_11_MAX_LENGTH + 1] = {0};

  TEST_ASSERT_FALSE_MESSAGE(wifi_get_ssid(ssid, sizeof(ssid)),
    "device: get_ssid should return false on empty NVS");
  TEST_ASSERT_FALSE_MESSAGE(wifi_get_password(pass, sizeof(pass)),
    "device: get_password should return false on empty NVS");

  restore_nvs();
  TEST_MESSAGE("empty NVS returns false, NVS restored");
}

static void wifi_test_overwrite_keeps_latest(void) {
  save_nvs();

  wifi_set_credentials("first_ssid", "first_pass");
  wifi_set_credentials("second_ssid", "second_pass");

  char ssid[CONFIG_WIFI_SSID_IEEE_802_11_MAX_LENGTH + 1] = {0};
  char pass[CONFIG_WIFI_PASS_IEEE_802_11_MAX_LENGTH + 1] = {0};

  wifi_get_ssid(ssid, sizeof(ssid));
  wifi_get_password(pass, sizeof(pass));

  TEST_ASSERT_EQUAL_STRING_MESSAGE("second_ssid", ssid,
    "device: SSID should be the latest written value");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("second_pass", pass,
    "device: password should be the latest written value");

  restore_nvs();
  TEST_MESSAGE("overwrite verified, NVS restored");
}

static void wifi_test_connect_fails_without_ssid(void) {
  save_nvs();

  Preferences preferences;
  preferences.begin(CONFIG_WIFI_NVS_NAMESPACE, false);
  preferences.remove("ssid");
  preferences.remove("pass");
  preferences.end();

  wifi_setup();
  TEST_ASSERT_FALSE_MESSAGE(wifi_connect(),
    "device: wifi_connect should return false when no SSID stored");

  restore_nvs();
  TEST_MESSAGE("connect fails without SSID, NVS restored");
}

static void wifi_test_ap_config_roundtrip(void) {
  save_nvs();

  wifi_set_ap_config("my-custom-ap", "secret123");

  char ssid[33] = {0};
  char pass[65] = {0};
  wifi_get_ap_ssid(ssid, sizeof(ssid));
  wifi_get_ap_password(pass, sizeof(pass));

  TEST_ASSERT_EQUAL_STRING_MESSAGE("my-custom-ap", ssid,
    "device: AP SSID mismatch after roundtrip");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("secret123", pass,
    "device: AP password mismatch after roundtrip");

  restore_nvs();
  TEST_MESSAGE("AP config roundtrip verified, NVS restored");
}

static void wifi_test_ap_default_ssid(void) {
  save_nvs();

  Preferences preferences;
  preferences.begin(CONFIG_WIFI_NVS_NAMESPACE, false);
  preferences.remove("ap_ssid");
  preferences.end();

  char ssid[33] = {0};
  wifi_get_ap_ssid(ssid, sizeof(ssid));

  TEST_ASSERT_EQUAL_STRING_MESSAGE(CONFIG_AP_SSID, ssid,
    "device: AP SSID should default to CONFIG_AP_SSID");

  restore_nvs();
  TEST_MESSAGE("AP default SSID verified, NVS restored");
}

static void wifi_test_ap_enabled_default_true(void) {
  save_nvs();

  Preferences preferences;
  preferences.begin(CONFIG_WIFI_NVS_NAMESPACE, false);
  preferences.remove("ap_on");
  preferences.end();

  TEST_ASSERT_TRUE_MESSAGE(wifi_get_ap_enabled(),
    "device: AP should be enabled by default");

  restore_nvs();
  TEST_MESSAGE("AP enabled default verified, NVS restored");
}

static void wifi_test_ap_enabled_toggle(void) {
  save_nvs();

  Preferences preferences;
  preferences.begin(CONFIG_WIFI_NVS_NAMESPACE, false);
  preferences.putBool("ap_on", false);
  preferences.end();

  TEST_ASSERT_FALSE_MESSAGE(wifi_get_ap_enabled(),
    "device: AP should be disabled after setting false");

  preferences.begin(CONFIG_WIFI_NVS_NAMESPACE, false);
  preferences.putBool("ap_on", true);
  preferences.end();

  TEST_ASSERT_TRUE_MESSAGE(wifi_get_ap_enabled(),
    "device: AP should be enabled after setting true");

  restore_nvs();
  TEST_MESSAGE("AP enabled toggle verified, NVS restored");
}

void wifi_run_tests(void) {
  it("user observes that wifi credentials can be saved and read from NVS",
     wifi_test_credentials_roundtrip);
  it("user observes that empty NVS returns false for credentials",
     wifi_test_empty_nvs_returns_false);
  it("user observes that overwriting credentials keeps the latest",
     wifi_test_overwrite_keeps_latest);
  it("user observes that wifi_connect fails without stored SSID",
     wifi_test_connect_fails_without_ssid);
  it("user observes that AP config can be saved and read from NVS",
     wifi_test_ap_config_roundtrip);
  it("user observes that AP SSID defaults to CONFIG_AP_SSID",
     wifi_test_ap_default_ssid);
  it("user observes that AP is enabled by default",
     wifi_test_ap_enabled_default_true);
  it("user observes that AP enabled flag can be toggled",
     wifi_test_ap_enabled_toggle);
}

#endif
