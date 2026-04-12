#include "wifi.h"
#include "../programs/led.h"
#include <ColorFormat.h>

#include <Arduino.h>
#include <WiFi.h>
#include <ESPmDNS.h>
#include "../util/preferences_guard.h"

static bool mdns_started = false;
static bool ap_active = false;

static const char wifi_ssid_slot[33] __attribute__((used, aligned(4))) =
  "@@WIFI_SSID@@";
static const char wifi_pass_slot[65] __attribute__((used, aligned(4))) =
  "@@WIFI_PASS@@";

void networking::wifi::sta::initialize() noexcept {
  static bool setup_done = false;
  if (setup_done) return;
  setup_done = true;

  WiFi.setAutoReconnect(true);
  WiFi.mode(WIFI_MODE_STA);

  WiFi.onEvent([](arduino_event_id_t event, arduino_event_info_t info) {
    switch (event) {
      case ARDUINO_EVENT_WIFI_STA_CONNECTED:
        Serial.printf("[wifi] %s\n", WiFi.eventName(event));
        break;

      case ARDUINO_EVENT_WIFI_STA_DISCONNECTED:
        Serial.printf("[wifi] %s reason: %s\n",
                      WiFi.eventName(event),
                      WiFi.disconnectReasonName(
                          (wifi_err_reason_t)info.wifi_sta_disconnected.reason));
        LED.set(RGB_YELLOW);
        break;

      case ARDUINO_EVENT_WIFI_STA_GOT_IP:
        Serial.printf("[wifi] %s %s\n", WiFi.eventName(event),
                      WiFi.localIP().toString().c_str());
        LED.set(RGB_GREEN);
        if (!mdns_started && MDNS.begin(config::HOSTNAME)) {
          MDNS.setInstanceName(config::HOSTNAME);
          MDNS.addService("ssh", "tcp", config::ssh::PORT);
          MDNS.addService("http", "tcp", config::http::PORT);
          MDNS.addServiceTxt("http", "tcp", "path", "/");
          MDNS.addServiceTxt("http", "tcp", "fw", ESP.getSdkVersion());
          Serial.printf("[mdns] %s.local\n", config::HOSTNAME);
          mdns_started = true;
        }
        break;

      default:
        break;
    }
  });
}

bool networking::wifi::sta::connect() noexcept {
  WiFi.setAutoReconnect(true);
  WiFi.disconnect(true);
  WiFi.mode(WIFI_MODE_STA);
  WiFi.setHostname(config::HOSTNAME);

#if defined(CONFIG_WIFI_SSID) && defined(CONFIG_WIFI_PASS)
  if (strlen(CONFIG_WIFI_SSID) > 0) {
    Serial.printf("[wifi] credentials from build flags: %s\n", CONFIG_WIFI_SSID);
    WiFi.begin(CONFIG_WIFI_SSID, CONFIG_WIFI_PASS);
  } else
#endif
  if (wifi_ssid_slot[0] != '@' && wifi_ssid_slot[0] != '\0') {
    Serial.printf("[wifi] credentials from embedded: %s\n", wifi_ssid_slot);
    WiFi.begin(wifi_ssid_slot, wifi_pass_slot);
  } else {
    WiFi.begin();
  }

  return WiFi.waitForConnectResult(config::wifi::CONNECT_TIMEOUT_MS) == WL_CONNECTED;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Access Point + Captive Portal
// ─────────────────────────────────────────────────────────────────────────────

void networking::wifi::ap::accessConfig(APConfig *config) noexcept {
  PreferencesGuard prefs(config::wifi::NVS_NAMESPACE, true);
  if (!prefs.ok() || prefs->getString("ap_ssid", config->ssid, sizeof(config->ssid)) == 0) {
    strncpy(config->ssid, config::wifi::ap::SSID, sizeof(config->ssid) - 1);
    config->ssid[sizeof(config->ssid) - 1] = '\0';
  }
  if (!prefs.ok() || prefs->getString("ap_pass", config->password, sizeof(config->password)) == 0) {
    strncpy(config->password, config::wifi::ap::PASSWORD, sizeof(config->password) - 1);
    config->password[sizeof(config->password) - 1] = '\0';
  }
}

void networking::wifi::ap::configure(const char *ssid, const char *password) noexcept {
  PreferencesGuard prefs(config::wifi::NVS_NAMESPACE, false);
  prefs->putString("ap_ssid", ssid);
  prefs->putString("ap_pass", password);
  Serial.printf("[wifi] AP config saved: ssid=%s\n", ssid);
}

void networking::wifi::ap::enable() noexcept {
  { PreferencesGuard prefs(config::wifi::NVS_NAMESPACE, false);
    prefs->putBool("ap_on", true); }

  if (ap_active) return;

  APConfig cfg = {};
  networking::wifi::ap::accessConfig(&cfg);

  WiFi.mode(WIFI_AP_STA);

  IPAddress ap_ip(192, 168, 4, 1);
  IPAddress gateway(192, 168, 4, 1);
  IPAddress subnet(255, 255, 255, 0);
  WiFi.softAPConfig(ap_ip, gateway, subnet);
  WiFi.softAP(cfg.ssid, cfg.password, config::wifi::ap::CHANNEL);

#if ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(5, 4, 2)
  WiFi.AP.enableDhcpCaptivePortal();
#endif

  ap_active = true;
  Serial.printf("[wifi] AP started: %s (%s)\n",
                cfg.ssid, ap_ip.toString().c_str());
}

void networking::wifi::ap::disable() noexcept {
  { PreferencesGuard prefs(config::wifi::NVS_NAMESPACE, false);
    prefs->putBool("ap_on", false); }

  if (!ap_active) return;

  WiFi.softAPdisconnect(true);

  if (WiFi.isConnected()) {
    WiFi.mode(WIFI_MODE_STA);
  }

  ap_active = false;
  Serial.println(F("[wifi] AP stopped"));
}

bool networking::wifi::ap::isActive() noexcept {
  return ap_active;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING


#include "wifi.h"
#include "../testing/it.h"
#include "../testing/nvs_helpers.h"

namespace networking::wifi { void test(void); }

#include <Arduino.h>
#include <WiFi.h>
#include <esp_wifi.h>

static WifiNvsSnapshot saved;
static void save_nvs(void) { wifi_nvs_save(&saved); }
static void restore_nvs(void) { wifi_nvs_restore(&saved); }

static void wifi_test_persistent_credentials(void) {
  TEST_MESSAGE("user verifies that WiFi.begin(ssid, pass) persists credentials");

  WiFi.begin("test_ssid_persist", "test_pass_persist");
  delay(100);
  WiFi.disconnect(true);

  wifi_config_t conf;
  esp_err_t err = esp_wifi_get_config(WIFI_IF_STA, &conf);
  TEST_ASSERT_EQUAL_MESSAGE(ESP_OK, err,
    "device: esp_wifi_get_config failed");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("test_ssid_persist", (const char *)conf.sta.ssid,
    "device: SSID not persisted by WiFi.begin()");

  TEST_MESSAGE("credentials persisted via built-in WiFi persistence");
}

static void wifi_test_connect_fails_without_ssid(void) {
  TEST_MESSAGE("user verifies wifi_connect fails when no credentials stored");

  WiFi.eraseAP();
  delay(100);

  networking::wifi::sta::initialize();
  TEST_ASSERT_FALSE_MESSAGE(networking::wifi::sta::connect(),
    "device: wifi_connect should return false when no SSID stored");

  TEST_MESSAGE("connect fails without SSID");
}

static void wifi_test_ap_config_roundtrip(void) {
  save_nvs();

  networking::wifi::ap::configure("my-custom-ap", "secret123");

  APConfig cfg = {};
  networking::wifi::ap::accessConfig(&cfg);

  TEST_ASSERT_EQUAL_STRING_MESSAGE("my-custom-ap", cfg.ssid,
    "device: AP SSID mismatch after roundtrip");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("secret123", cfg.password,
    "device: AP password mismatch after roundtrip");

  restore_nvs();
  TEST_MESSAGE("AP config roundtrip verified, NVS restored");
}

static void wifi_test_ap_default_ssid(void) {
  save_nvs();

  Preferences preferences;
  preferences.begin(config::wifi::NVS_NAMESPACE, false);
  preferences.remove("ap_ssid");
  preferences.end();

  APConfig cfg = {};
  networking::wifi::ap::accessConfig(&cfg);

  TEST_ASSERT_EQUAL_STRING_MESSAGE(config::wifi::ap::SSID, cfg.ssid,
    "device: AP SSID should default to config::wifi::ap::SSID");

  restore_nvs();
  TEST_MESSAGE("AP default SSID verified, NVS restored");
}

static void wifi_test_ap_enabled_default_true(void) {
  save_nvs();

  Preferences preferences;
  preferences.begin(config::wifi::NVS_NAMESPACE, false);
  preferences.remove("ap_on");
  preferences.end();

  PreferencesGuard prefs(config::wifi::NVS_NAMESPACE, true);
  bool enabled = prefs.ok() ? prefs->getBool("ap_on", true) : true;
  TEST_ASSERT_TRUE_MESSAGE(enabled,
    "device: AP should be enabled by default");

  restore_nvs();
  TEST_MESSAGE("AP enabled default verified, NVS restored");
}

static void wifi_test_ap_enabled_toggle(void) {
  save_nvs();

  Preferences preferences;
  preferences.begin(config::wifi::NVS_NAMESPACE, false);
  preferences.putBool("ap_on", false);
  preferences.end();

  {
    PreferencesGuard prefs(config::wifi::NVS_NAMESPACE, true);
    TEST_ASSERT_FALSE_MESSAGE(prefs->getBool("ap_on", true),
      "device: AP should be disabled after setting false");
  }

  preferences.begin(config::wifi::NVS_NAMESPACE, false);
  preferences.putBool("ap_on", true);
  preferences.end();

  {
    PreferencesGuard prefs(config::wifi::NVS_NAMESPACE, true);
    TEST_ASSERT_TRUE_MESSAGE(prefs->getBool("ap_on", true),
      "device: AP should be enabled after setting true");
  }

  restore_nvs();
  TEST_MESSAGE("AP enabled toggle verified, NVS restored");
}

void networking::wifi::test(void) {
  it("user observes that WiFi.begin persists credentials via ESP-IDF",
     wifi_test_persistent_credentials);
  it("user observes that wifi_connect fails without stored SSID",
     wifi_test_connect_fails_without_ssid);
  it("user observes that AP config can be saved and read from NVS",
     wifi_test_ap_config_roundtrip);
  it("user observes that AP SSID defaults to config::wifi::ap::SSID",
     wifi_test_ap_default_ssid);
  it("user observes that AP is enabled by default",
     wifi_test_ap_enabled_default_true);
  it("user observes that AP enabled flag can be toggled",
     wifi_test_ap_enabled_toggle);
}

#endif
