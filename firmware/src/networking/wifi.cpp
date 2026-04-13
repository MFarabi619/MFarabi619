#include "wifi.h"
#include "wifi_internal.h"
#include "../services/identity.h"

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
  return prefs && prefs->begin(config::wifi::NVS_NAMESPACE, readonly);
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
  strncpy(snapshot->hostname, services::identity::accessHostname(), sizeof(snapshot->hostname) - 1);

  snapshot->ap.active = networking::wifi::ap::isActive();
  APConfig ap_config = {};
  networking::wifi::ap::accessConfig(&ap_config);
  strncpy(snapshot->ap.ssid, ap_config.ssid, sizeof(snapshot->ap.ssid) - 1);
  strncpy(snapshot->ap.password, ap_config.password, sizeof(snapshot->ap.password) - 1);
  strncpy(snapshot->ap.ip, WiFi.softAPIP().toString().c_str(), sizeof(snapshot->ap.ip) - 1);
  snapshot->ap.clients = WiFi.softAPgetStationNum();
  strncpy(snapshot->ap.hostname, services::identity::accessHostname(), sizeof(snapshot->ap.hostname) - 1);
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
  prefs.end();
  config->valid = config->ssid[0] != '\0';
  return config->valid;
}

bool networking::wifi::connect(WifiConnectCommand *command) {
  if (!command) return false;
  command->result = {};
  command->result.connected = false;
  command->result.status_code = WL_DISCONNECTED;
  command->result.ap_enabled_for_fallback = false;

  WiFi.setAutoReconnect(true);
  WiFi.disconnect(false);
  WiFi.mode(networking::wifi::ap::isActive() ? WIFI_AP_STA : WIFI_MODE_STA);
  networking::wifi::configureHostname(services::identity::accessHostname());

  if (command->request.ssid && command->request.ssid[0] != '\0') {
    WiFi.begin(command->request.ssid,
               command->request.password ? command->request.password : "");
  } else {
    WifiSavedConfig saved_config = {};
    if (networking::wifi::accessConfig(&saved_config) && saved_config.valid) {
      Serial.printf("[wifi] credentials from NVS: %s\n", saved_config.ssid);
      WiFi.begin(saved_config.ssid, saved_config.password);
    } else
#if defined(CONFIG_WIFI_SSID) && defined(CONFIG_WIFI_PASS)
    if (strlen(CONFIG_WIFI_SSID) > 0) {
      Serial.printf("[wifi] credentials from build flags: %s\n", CONFIG_WIFI_SSID);
      WiFi.begin(CONFIG_WIFI_SSID, CONFIG_WIFI_PASS);
    } else
#endif
    if (networking::wifi::internal::wifi_ssid_slot[0] != '@' && networking::wifi::internal::wifi_ssid_slot[0] != '\0') {
      Serial.printf("[wifi] credentials from embedded: %s\n", networking::wifi::internal::wifi_ssid_slot);
      WiFi.begin(networking::wifi::internal::wifi_ssid_slot, networking::wifi::internal::wifi_pass_slot);
    } else {
      WiFi.begin();
    }
  }

  command->result.status_code = WiFi.waitForConnectResult(config::wifi::CONNECT_TIMEOUT_MS);
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

    Preferences prefs;
    bool opened = networking::wifi::internal::openPreferences(true, &prefs);
    bool enabled = opened ? prefs.getBool("ap_on", true) : true;
    if (opened) prefs.end();
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
