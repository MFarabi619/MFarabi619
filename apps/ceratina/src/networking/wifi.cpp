#include <networking/wifi.h>
#include "wifi_internal.h"
#include <identity.h>
#include <led.h>
#include "../services/preferences.h"

#include <Arduino.h>
#include <Preferences.h>
#include <WiFi.h>
bool networking::wifi::internal::mdns_started = false;
bool networking::wifi::internal::ap_active = false;

const char networking::wifi::internal::wifi_ssid_slot[33] __attribute__((used, aligned(4))) =
  "@@WIFI_SSID@@";
const char networking::wifi::internal::wifi_pass_slot[65] __attribute__((used, aligned(4))) =
  "@@WIFI_PASS@@";

bool networking::wifi::internal::openPreferences(bool readonly, Preferences *prefs) {
  return services::preferences::open(config::wifi::NVS_NAMESPACE, readonly, prefs);
}

bool networking::wifi::accessSnapshot(NetworkStatusSnapshot *snapshot) {
  if (!snapshot) return false;
  memset(snapshot, 0, sizeof(*snapshot));

  snapshot->connected = WiFi.isConnected();
  snapshot->rssi = snapshot->connected ? WiFi.RSSI() : 0;
  snapshot->channel = snapshot->connected ? WiFi.channel() : 0;

  strncpy(snapshot->ssid, WiFi.SSID().c_str(), sizeof(snapshot->ssid) - 1);
  strncpy(snapshot->bssid, WiFi.BSSIDstr().c_str(), sizeof(snapshot->bssid) - 1);
  strncpy(snapshot->ip, WiFi.localIP().toString().c_str(), sizeof(snapshot->ip) - 1);
  strncpy(snapshot->gateway, WiFi.gatewayIP().toString().c_str(), sizeof(snapshot->gateway) - 1);
  strncpy(snapshot->subnet, WiFi.subnetMask().toString().c_str(), sizeof(snapshot->subnet) - 1);
  strncpy(snapshot->dns, WiFi.dnsIP().toString().c_str(), sizeof(snapshot->dns) - 1);
  strncpy(snapshot->mac, WiFi.macAddress().c_str(), sizeof(snapshot->mac) - 1);
  strncpy(snapshot->hostname, services::identity::access_hostname(), sizeof(snapshot->hostname) - 1);

  snapshot->ap.active = networking::wifi::ap::isActive();
  APConfig ap_config = {};
  networking::wifi::ap::accessConfig(&ap_config);
  strncpy(snapshot->ap.ssid, ap_config.ssid, sizeof(snapshot->ap.ssid) - 1);
  strncpy(snapshot->ap.password, ap_config.password, sizeof(snapshot->ap.password) - 1);
  strncpy(snapshot->ap.ip, WiFi.softAPIP().toString().c_str(), sizeof(snapshot->ap.ip) - 1);
  snapshot->ap.clients = WiFi.softAPgetStationNum();
  strncpy(snapshot->ap.hostname, services::identity::access_hostname(), sizeof(snapshot->ap.hostname) - 1);
  strncpy(snapshot->ap.mac, WiFi.softAPmacAddress().c_str(), sizeof(snapshot->ap.mac) - 1);
  return true;
}

bool networking::wifi::accessConfig(WifiSavedConfig *config) {
  if (!config) return false;
  memset(config, 0, sizeof(*config));

  Preferences prefs;
  if (!networking::wifi::internal::openPreferences(true, &prefs)) return false;

  bool has_ssid = prefs.getString("sta_ssid", config->ssid, sizeof(config->ssid)) > 0;
  bool has_password = prefs.getString("sta_pass", config->password, sizeof(config->password)) >= 0;
  prefs.getString("sta_identity", config->identity, sizeof(config->identity));
  prefs.getString("sta_username", config->username, sizeof(config->username));
  config->is_enterprise = prefs.getBool("sta_enterprise", false);
  prefs.end();
  config->valid = has_ssid;
  return has_ssid && has_password;
}

bool networking::wifi::storeConfig(WifiSavedConfig *config) {
  if (!config) return false;
  Preferences prefs;
  if (!networking::wifi::internal::openPreferences(false, &prefs)) return false;

  prefs.putString("sta_ssid", config->ssid);
  prefs.putString("sta_pass", config->password);
  prefs.putString("sta_identity", config->identity);
  prefs.putString("sta_username", config->username);
  prefs.putBool("sta_enterprise", config->is_enterprise);
  prefs.end();
  config->valid = config->ssid[0] != '\0';
  return config->valid;
}

bool networking::wifi::clearConfig() {
  Preferences prefs;
  if (!networking::wifi::internal::openPreferences(false, &prefs)) return false;
  prefs.remove("sta_ssid");
  prefs.remove("sta_pass");
  prefs.remove("sta_identity");
  prefs.remove("sta_username");
  prefs.remove("sta_enterprise");
  prefs.end();
  WiFi.disconnect(true, true);
  return true;
}

bool networking::wifi::connect(WifiConnectCommand *command) {
  if (!command) return false;
  command->result = {};
  command->result.connected = false;
  command->result.status_code = WL_DISCONNECTED;
  command->result.ap_enabled_for_fallback = false;

  WiFi.setAutoReconnect(false);
  WiFi.disconnect(false);
  WiFi.mode(networking::wifi::ap::isActive() ? WIFI_AP_STA : WIFI_MODE_STA);
  networking::wifi::configure_hostname(services::identity::access_hostname());

  if (command->request.ssid && command->request.ssid[0] != '\0') {
    if (command->request.is_enterprise) {
      Serial.printf("[wifi] enterprise connect: %s\n", command->request.ssid);
      WiFi.begin(command->request.ssid, WPA2_AUTH_PEAP,
                 command->request.identity ? command->request.identity : "",
                 command->request.username ? command->request.username : "",
                 command->request.password ? command->request.password : "");
    } else {
      WiFi.begin(command->request.ssid,
                 command->request.password ? command->request.password : "");
    }
  } else {
    WifiSavedConfig saved_config = {};
    if (networking::wifi::accessConfig(&saved_config) && saved_config.valid) {
      Serial.printf("[wifi] credentials from NVS: %s\n", saved_config.ssid);
      if (saved_config.is_enterprise) {
        WiFi.begin(saved_config.ssid, WPA2_AUTH_PEAP,
                   saved_config.identity, saved_config.username, saved_config.password);
      } else {
        WiFi.begin(saved_config.ssid, saved_config.password);
      }
    } else
#if defined(CONFIG_WIFI_SSID) && defined(CONFIG_WIFI_PASS)
    if (strlen(CONFIG_WIFI_SSID) > 0) {
      Serial.printf("[wifi] credentials from build flags: %s\n", CONFIG_WIFI_SSID);
#if CONFIG_WIFI_ENTERPRISE
      WiFi.begin(CONFIG_WIFI_SSID, WPA2_AUTH_PEAP,
                 CONFIG_WIFI_IDENTITY, CONFIG_WIFI_USERNAME, CONFIG_WIFI_PASS);
#else
      WiFi.begin(CONFIG_WIFI_SSID, CONFIG_WIFI_PASS);
#endif
    } else
#endif
    if (networking::wifi::internal::wifi_ssid_slot[0] != '@' && networking::wifi::internal::wifi_ssid_slot[0] != '\0') {
      Serial.printf("[wifi] credentials from embedded: %s\n", networking::wifi::internal::wifi_ssid_slot);
      WiFi.begin(networking::wifi::internal::wifi_ssid_slot, networking::wifi::internal::wifi_pass_slot);
    } else {
      WiFi.begin();
    }
  }

  uint8_t saved_brightness = LED.getBrightness();
  unsigned long started_at = millis();
  unsigned long last_frame_at = 0;
  command->result.status_code = WiFi.status();

  while (millis() - started_at < config::wifi::CONNECT_TIMEOUT_MS) {
    wl_status_t status = WiFi.status();
    if (status == WL_CONNECTED
        || status == WL_CONNECT_FAILED
        || status == WL_NO_SSID_AVAIL
        || status == WL_CONNECTION_LOST) {
      command->result.status_code = status;
      break;
    }

    unsigned long now = millis();
    if (now - last_frame_at >= config::led::FRAME_MS) {
      unsigned long phase = (now - started_at) % 1200;
      unsigned long ramp = phase < 600 ? phase : (1200 - phase);
      uint8_t pulsed_brightness = 32 + static_cast<uint8_t>((saved_brightness * ramp) / 600);
      LED.setBrightness(pulsed_brightness);
      LED.set(colors::Yellow);
      last_frame_at = now;
    }

    delay(config::led::FRAME_MS);
    command->result.status_code = status;
  }

  LED.setBrightness(saved_brightness);
  command->result.connected = (command->result.status_code == WL_CONNECTED);

  if (!command->result.connected && command->request.enable_ap_fallback
      && !networking::wifi::ap::isActive()) {
    networking::wifi::ap::enable();
    command->result.ap_enabled_for_fallback = true;
  }

  return command->result.connected;
}

bool networking::wifi::scan(WifiScanCommand *command) {
  if (!command || !command->results || command->max_results == 0) return false;
  command->result_count = -1;

  WiFi.scanDelete();
  int16_t count = WiFi.scanNetworks();
  if (count < 0) return false;

  int16_t limit = (count < (int16_t)command->max_results) ? count : (int16_t)command->max_results;
  for (int16_t index = 0; index < limit; index++) {
    memset(&command->results[index], 0, sizeof(command->results[index]));
    strlcpy(command->results[index].ssid, WiFi.SSID(index).c_str(), sizeof(command->results[index].ssid));
    strlcpy(command->results[index].bssid, WiFi.BSSIDstr(index).c_str(), sizeof(command->results[index].bssid));
    command->results[index].rssi = WiFi.RSSI(index);
    command->results[index].channel = WiFi.channel(index);

    const char *encryption = "unknown";
    switch (WiFi.encryptionType(index)) {
      case WIFI_AUTH_OPEN:            encryption = "open"; break;
      case WIFI_AUTH_WEP:             encryption = "wep"; break;
      case WIFI_AUTH_WPA_PSK:         encryption = "wpa"; break;
      case WIFI_AUTH_WPA2_PSK:        encryption = "wpa2"; break;
      case WIFI_AUTH_WPA_WPA2_PSK:    encryption = "wpa_wpa2"; break;
      case WIFI_AUTH_WPA2_ENTERPRISE: encryption = "wpa2_enterprise"; break;
      case WIFI_AUTH_WPA3_PSK:        encryption = "wpa3"; break;
      case WIFI_AUTH_WPA2_WPA3_PSK:   encryption = "wpa2_wpa3"; break;
      default:                        break;
    }
    strlcpy(command->results[index].encryption, encryption, sizeof(command->results[index].encryption));
    command->results[index].open = (WiFi.encryptionType(index) == WIFI_AUTH_OPEN);
  }

  WiFi.scanDelete();
  command->result_count = count;
  return true;
}


// ─────────────────────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING


#include <networking/wifi.h>
#include <testing/utils.h>


namespace networking::wifi { void test(void); }

#include <Arduino.h>
#include <WiFi.h>
#include <esp_wifi.h>

static WifiNvsSnapshot saved;
static void save_nvs(void) { wifi_nvs_save(&saved); }
static void restore_nvs(void) { wifi_nvs_restore(&saved); }

static void test_wifi_persistent_credentials(void) {
  WHEN("WiFi.begin(ssid, pass) is called");

  WiFi.begin("test_ssid_persist", "test_pass_persist");
  delay(100);
  WiFi.disconnect(true);

  wifi_config_t conf;
  esp_err_t err = esp_wifi_get_config(WIFI_IF_STA, &conf);
  TEST_ASSERT_EQUAL_MESSAGE(ESP_OK, err,
    "device: esp_wifi_get_config failed");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("test_ssid_persist", (const char *)conf.sta.ssid,
    "device: SSID not persisted by WiFi.begin()");

}

static void test_wifi_connect_fails_without_ssid(void) {
  GIVEN("no WiFi credentials are stored");

  save_nvs();

  Preferences preferences;
  preferences.begin(config::wifi::NVS_NAMESPACE, false);
  preferences.remove("sta_ssid");
  preferences.remove("sta_pass");
  preferences.end();

  WiFi.disconnect(true, true);
  WiFi.eraseAP();
  delay(100);

#if defined(CONFIG_WIFI_SSID) && defined(CONFIG_WIFI_PASS)
  if (strlen(CONFIG_WIFI_SSID) > 0) {
    restore_nvs();
    TEST_IGNORE_MESSAGE("build-flag WiFi credentials configured — skipping no-SSID failure assertion");
  }
#endif

  if (networking::wifi::internal::wifi_ssid_slot[0] != '@'
      && networking::wifi::internal::wifi_ssid_slot[0] != '\0') {
    restore_nvs();
    TEST_IGNORE_MESSAGE("embedded WiFi credentials configured — skipping no-SSID failure assertion");
  }

  WHEN("wifi_connect is called");
  networking::wifi::sta::initialize();
  TEST_ASSERT_FALSE_MESSAGE(networking::wifi::sta::connect(),
    "device: wifi_connect should return false when no SSID stored");

  restore_nvs();
}

static void test_wifi_saved_sta_config_roundtrip(void) {
  WHEN("STA config is stored and read back");
  save_nvs();

  WifiSavedConfig written = {};
  strlcpy(written.ssid, "test-sta-ssid", sizeof(written.ssid));
  strlcpy(written.password, "test-sta-pass", sizeof(written.password));

  TEST_ASSERT_TRUE_MESSAGE(networking::wifi::storeConfig(&written),
    "device: storing WiFi STA config should succeed");
  TEST_ASSERT_TRUE_MESSAGE(written.valid,
    "device: stored WiFi STA config should be marked valid");

  WifiSavedConfig read_back = {};
  TEST_ASSERT_TRUE_MESSAGE(networking::wifi::accessConfig(&read_back),
    "device: reading WiFi STA config should succeed after store");
  TEST_ASSERT_TRUE_MESSAGE(read_back.valid,
    "device: read-back WiFi STA config should be marked valid");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("test-sta-ssid", read_back.ssid,
    "device: STA SSID mismatch after config roundtrip");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("test-sta-pass", read_back.password,
    "device: STA password mismatch after config roundtrip");

  restore_nvs();
}

static void test_wifi_connect_prefers_explicit_credentials(void) {
  GIVEN("a saved STA config exists");
  save_nvs();

  WifiSavedConfig saved_config = {};
  strlcpy(saved_config.ssid, "saved-ssid", sizeof(saved_config.ssid));
  strlcpy(saved_config.password, "saved-password", sizeof(saved_config.password));
  TEST_ASSERT_TRUE_MESSAGE(networking::wifi::storeConfig(&saved_config),
    "device: storing saved STA config should succeed");

  WHEN("connect is called with explicit credentials");
  WifiConnectCommand command = {
    .request = {
      .ssid = "request-ssid",
      .password = "request-password",
      .enable_ap_fallback = false,
    },
    .result = {},
  };

  networking::wifi::connect(&command);
  delay(100);

  THEN("the explicit credentials override saved config");
  wifi_config_t station_config = {};
  esp_err_t err = esp_wifi_get_config(WIFI_IF_STA, &station_config);
  TEST_ASSERT_EQUAL_MESSAGE(ESP_OK, err,
    "device: esp_wifi_get_config should succeed after explicit connect request");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("request-ssid", (const char *)station_config.sta.ssid,
    "device: explicit connect request should override saved SSID");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("request-password", (const char *)station_config.sta.password,
    "device: explicit connect request should override saved password");

  WiFi.disconnect(true);
  restore_nvs();
}

static void test_wifi_connect_uses_saved_config(void) {
  GIVEN("a saved STA config exists and no request SSID is provided");
  save_nvs();

  WifiSavedConfig saved_config = {};
  strlcpy(saved_config.ssid, "saved-only-ssid", sizeof(saved_config.ssid));
  strlcpy(saved_config.password, "saved-only-password", sizeof(saved_config.password));
  TEST_ASSERT_TRUE_MESSAGE(networking::wifi::storeConfig(&saved_config),
    "device: storing fallback STA config should succeed");

  WHEN("connect is called with empty request SSID");
  WifiConnectCommand command = {
    .request = {
      .ssid = "",
      .password = "",
      .enable_ap_fallback = false,
    },
    .result = {},
  };

  networking::wifi::connect(&command);
  delay(100);

  THEN("the saved config is used");
  wifi_config_t station_config = {};
  esp_err_t err = esp_wifi_get_config(WIFI_IF_STA, &station_config);
  TEST_ASSERT_EQUAL_MESSAGE(ESP_OK, err,
    "device: esp_wifi_get_config should succeed after saved-config connect request");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("saved-only-ssid", (const char *)station_config.sta.ssid,
    "device: saved STA config should be used when request SSID is empty");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("saved-only-password", (const char *)station_config.sta.password,
    "device: saved STA password should be used when request SSID is empty");

  WiFi.disconnect(true);
  restore_nvs();
}

static void test_wifi_ap_fallback_on_failed_connect(void) {
  GIVEN("AP is disabled and WiFi is disconnected");
  save_nvs();

  networking::wifi::ap::disable();
  WiFi.disconnect(true, true);
  delay(100);

  WifiConnectCommand command = {
    .request = {
      .ssid = "ssid-that-should-not-exist",
      .password = "definitely-not-the-right-password",
      .enable_ap_fallback = true,
    },
    .result = {},
  };

  WHEN("connect fails with fallback enabled");
  TEST_ASSERT_FALSE_MESSAGE(networking::wifi::connect(&command),
    "device: WiFi connect should fail with intentionally invalid credentials");
  TEST_ASSERT_FALSE_MESSAGE(command.result.connected,
    "device: connect result should report disconnected after failed connect");

  THEN("AP fallback is activated");
  TEST_ASSERT_TRUE_MESSAGE(command.result.ap_enabled_for_fallback,
    "device: AP fallback should be enabled after failed connect when requested");
  TEST_ASSERT_TRUE_MESSAGE(networking::wifi::ap::isActive(),
    "device: AP should be active after fallback-enabled failed connect");

  networking::wifi::ap::disable();
  WiFi.disconnect(true, true);
  restore_nvs();
}

static void test_wifi_no_ap_fallback_without_request(void) {
  GIVEN("AP is disabled and WiFi is disconnected");
  save_nvs();

  networking::wifi::ap::disable();
  WiFi.disconnect(true, true);
  delay(100);

  WifiConnectCommand command = {
    .request = {
      .ssid = "ssid-that-should-not-exist",
      .password = "definitely-not-the-right-password",
      .enable_ap_fallback = false,
    },
    .result = {},
  };

  WHEN("connect fails without fallback requested");
  TEST_ASSERT_FALSE_MESSAGE(networking::wifi::connect(&command),
    "device: WiFi connect should fail with intentionally invalid credentials");
  TEST_ASSERT_FALSE_MESSAGE(command.result.connected,
    "device: connect result should report disconnected after failed connect");

  THEN("AP remains inactive");
  TEST_ASSERT_FALSE_MESSAGE(command.result.ap_enabled_for_fallback,
    "device: AP fallback should stay disabled when not requested");
  TEST_ASSERT_FALSE_MESSAGE(networking::wifi::ap::isActive(),
    "device: AP should remain inactive after failed connect without fallback request");

  WiFi.disconnect(true, true);
  restore_nvs();
}

static void test_wifi_snapshot_ap_fallback_state(void) {
  GIVEN("a failed connect with AP fallback enabled");
  save_nvs();

  networking::wifi::ap::disable();
  WiFi.disconnect(true, true);
  delay(100);

  WifiConnectCommand command = {
    .request = {
      .ssid = "ssid-that-should-not-exist",
      .password = "definitely-not-the-right-password",
      .enable_ap_fallback = true,
    },
    .result = {},
  };

  TEST_ASSERT_FALSE_MESSAGE(networking::wifi::connect(&command),
    "device: WiFi connect should fail before snapshot fallback verification");
  TEST_ASSERT_TRUE_MESSAGE(command.result.ap_enabled_for_fallback,
    "device: AP fallback should be active before snapshot verification");

  THEN("the snapshot reflects AP fallback state");
  NetworkStatusSnapshot snapshot = {};
  TEST_ASSERT_TRUE_MESSAGE(networking::wifi::accessSnapshot(&snapshot),
    "device: accessSnapshot should succeed after AP fallback activation");

  TEST_ASSERT_FALSE_MESSAGE(snapshot.connected,
    "device: station snapshot should report disconnected after failed connect");
  TEST_ASSERT_TRUE_MESSAGE(snapshot.ap.active,
    "device: AP snapshot should report active after fallback activation");
  TEST_ASSERT_EQUAL_STRING_MESSAGE(services::identity::access_hostname(), snapshot.hostname,
    "device: station snapshot hostname should match identity hostname");
  TEST_ASSERT_EQUAL_STRING_MESSAGE(services::identity::access_hostname(), snapshot.ap.hostname,
    "device: AP snapshot hostname should match identity hostname");

  APConfig ap_config = {};
  networking::wifi::ap::accessConfig(&ap_config);
  TEST_ASSERT_EQUAL_STRING_MESSAGE(ap_config.ssid, snapshot.ap.ssid,
    "device: AP snapshot SSID should match AP config");
  TEST_ASSERT_EQUAL_STRING_MESSAGE(ap_config.password, snapshot.ap.password,
    "device: AP snapshot password should match AP config");
  TEST_ASSERT_TRUE_MESSAGE(snapshot.ap.ip[0] != '\0',
    "device: AP snapshot IP should be populated when AP is active");
  TEST_ASSERT_TRUE_MESSAGE(snapshot.ap.mac[0] != '\0',
    "device: AP snapshot MAC should be populated when AP is active");

  networking::wifi::ap::disable();
  WiFi.disconnect(true, true);
  restore_nvs();
}

static void test_wifi_snapshot_rejects_null(void) {
  THEN("null snapshot buffer is rejected");
  TEST_ASSERT_FALSE_MESSAGE(networking::wifi::accessSnapshot(nullptr),
    "device: accessSnapshot should reject null output buffer");
}

static void test_wifi_config_rejects_null(void) {
  THEN("null config buffer is rejected");
  TEST_ASSERT_FALSE_MESSAGE(networking::wifi::accessConfig(nullptr),
    "device: accessConfig should reject null output buffer");
}

static void test_wifi_store_config_rejects_null(void) {
  THEN("null config input is rejected");
  TEST_ASSERT_FALSE_MESSAGE(networking::wifi::storeConfig(nullptr),
    "device: storeConfig should reject null config buffer");
}

static void test_wifi_connect_rejects_null(void) {
  THEN("null connect command is rejected");
  TEST_ASSERT_FALSE_MESSAGE(networking::wifi::connect(nullptr),
    "device: connect should reject null command buffer");
}

static void test_wifi_snapshot_ap_inactive(void) {
  GIVEN("the AP is disabled");
  save_nvs();

  networking::wifi::ap::disable();
  WiFi.disconnect(true, true);
  delay(100);

  THEN("the snapshot reports AP inactive");
  NetworkStatusSnapshot snapshot = {};
  TEST_ASSERT_TRUE_MESSAGE(networking::wifi::accessSnapshot(&snapshot),
    "device: accessSnapshot should succeed when AP is disabled");
  TEST_ASSERT_FALSE_MESSAGE(snapshot.ap.active,
    "device: AP snapshot should report inactive when AP is disabled");
  TEST_ASSERT_EQUAL_UINT16_MESSAGE(0, snapshot.ap.clients,
    "device: AP snapshot should report zero clients when AP is disabled");

  restore_nvs();
}

static void test_wifi_ap_config_roundtrip(void) {
  WHEN("AP config is stored and read back");
  save_nvs();

  APConfigureCommand command = {
    .config = {},
    .snapshot = {},
  };
  strlcpy(command.config.ssid, "my-custom-ap", sizeof(command.config.ssid));
  strlcpy(command.config.password, "secret123", sizeof(command.config.password));
  networking::wifi::ap::applyConfig(&command);

  APConfig cfg = {};
  networking::wifi::ap::accessConfig(&cfg);

  TEST_ASSERT_EQUAL_STRING_MESSAGE("my-custom-ap", cfg.ssid,
    "device: AP SSID mismatch after roundtrip");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("secret123", cfg.password,
    "device: AP password mismatch after roundtrip");

  restore_nvs();
}

static void test_wifi_ap_default_ssid(void) {
  GIVEN("the AP SSID key is removed from NVS");
  save_nvs();

  Preferences preferences;
  preferences.begin(config::wifi::NVS_NAMESPACE, false);
  preferences.remove("ap_ssid");
  preferences.end();

  THEN("the AP SSID defaults to the configured value");
  APConfig cfg = {};
  networking::wifi::ap::accessConfig(&cfg);

  TEST_ASSERT_EQUAL_STRING_MESSAGE(config::wifi::ap::SSID, cfg.ssid,
    "device: AP SSID should default to config::wifi::ap::SSID");

  restore_nvs();
}

static void test_wifi_ap_enabled_default_true(void) {
  GIVEN("the ap_on key is removed from NVS");
  save_nvs();

  Preferences preferences;
  preferences.begin(config::wifi::NVS_NAMESPACE, false);
  preferences.remove("ap_on");
  preferences.end();

    THEN("AP is enabled by default");
    Preferences prefs;
    bool opened = networking::wifi::internal::openPreferences(true, &prefs);
    bool enabled = opened ? prefs.getBool("ap_on", true) : true;
    if (opened) prefs.end();
    TEST_ASSERT_TRUE_MESSAGE(enabled,
      "device: AP should be enabled by default");

  restore_nvs();
}

static void test_wifi_ap_enabled_toggle(void) {
  WHEN("the AP enabled flag is toggled");
  save_nvs();

  Preferences preferences;
  preferences.begin(config::wifi::NVS_NAMESPACE, false);
  preferences.putBool("ap_on", false);
  preferences.end();

    {
      Preferences prefs;
      TEST_ASSERT_TRUE_MESSAGE(networking::wifi::internal::openPreferences(true, &prefs),
        "device: wifi NVS namespace must be readable");
      TEST_ASSERT_FALSE_MESSAGE(prefs.getBool("ap_on", true),
        "device: AP should be disabled after setting false");
      prefs.end();
    }

  preferences.begin(config::wifi::NVS_NAMESPACE, false);
  preferences.putBool("ap_on", true);
  preferences.end();

    {
      Preferences prefs;
      TEST_ASSERT_TRUE_MESSAGE(networking::wifi::internal::openPreferences(true, &prefs),
        "device: wifi NVS namespace must be readable");
      TEST_ASSERT_TRUE_MESSAGE(prefs.getBool("ap_on", true),
        "device: AP should be enabled after setting true");
      prefs.end();
    }

  restore_nvs();
}

void networking::wifi::test(void) {
  MODULE("WiFi");
  RUN_TEST(test_wifi_snapshot_rejects_null);
  RUN_TEST(test_wifi_config_rejects_null);
  RUN_TEST(test_wifi_store_config_rejects_null);
  RUN_TEST(test_wifi_connect_rejects_null);
  RUN_TEST(test_wifi_saved_sta_config_roundtrip);
  RUN_TEST(test_wifi_connect_prefers_explicit_credentials);
  RUN_TEST(test_wifi_connect_uses_saved_config);
  RUN_TEST(test_wifi_ap_fallback_on_failed_connect);
  RUN_TEST(test_wifi_no_ap_fallback_without_request);
  RUN_TEST(test_wifi_snapshot_ap_fallback_state);
  RUN_TEST(test_wifi_snapshot_ap_inactive);
  RUN_TEST(test_wifi_connect_fails_without_ssid);
  RUN_TEST(test_wifi_ap_config_roundtrip);
  RUN_TEST(test_wifi_ap_default_ssid);
  RUN_TEST(test_wifi_ap_enabled_default_true);
  RUN_TEST(test_wifi_ap_enabled_toggle);
}

#endif
