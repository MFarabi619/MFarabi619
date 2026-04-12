#include "provisioning.h"
#include "../config.h"

#include <Arduino.h>
#include <WiFi.h>
#include <esp_wifi.h>
#include "../util/preferences_guard.h"

bool boot::provisioning::isEnabled(void) {
  return CERATINA_PROV_ENABLED;
}

static bool get_prov_string(const char *key, char *buf, size_t len) {
  PreferencesGuard prefs(config::provisioning::NVS_NAMESPACE, true);
  if (!prefs.ok()) return false;
  return prefs->getString(key, buf, len) > 0;
}

bool boot::provisioning::isProvisioned(void) {
  wifi_config_t conf;
  if (esp_wifi_get_config(WIFI_IF_STA, &conf) == ESP_OK && conf.sta.ssid[0] != '\0')
    return true;

#if defined(CONFIG_WIFI_SSID) && defined(CONFIG_WIFI_PASS)
  if (strlen(CONFIG_WIFI_SSID) > 0) return true;
#endif

  return false;
}

void boot::provisioning::reset(void) {
  { PreferencesGuard prefs(config::provisioning::NVS_NAMESPACE, false);
    if (prefs.ok()) prefs->clear(); }
  { PreferencesGuard prefs(config::wifi::NVS_NAMESPACE, false);
    if (prefs.ok()) prefs->clear(); }
  WiFi.disconnect(true, true);  // erases ESP-IDF stored STA credentials
  Serial.println(F("[prov] reset — credentials cleared"));
}

bool boot::provisioning::accessUsername(char *buf, size_t len) {
  return get_prov_string("username", buf, len);
}

bool boot::provisioning::accessAPIKey(char *buf, size_t len) {
  return get_prov_string("api_key", buf, len);
}

bool boot::provisioning::accessDeviceName(char *buf, size_t len) {
  return get_prov_string("device_name", buf, len);
}

#if CERATINA_PROV_ENABLED

#include <ArduinoJson.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLESecurity.h>

#define PROV_CHAR_SSID_UUID     "ceaa0002-b5a3-f393-e0a9-e50e24dcca9e"
#define PROV_CHAR_PASSWORD_UUID "ceaa0003-b5a3-f393-e0a9-e50e24dcca9e"
#define PROV_CHAR_STATUS_UUID   "ceaa0004-b5a3-f393-e0a9-e50e24dcca9e"

static BLEServer *prov_server = nullptr;
static BLECharacteristic *status_char = nullptr;
static volatile bool prov_credentials_received = false;
static volatile bool prov_done = false;

static char prov_ssid[33] = {0};
static char prov_pass[65] = {0};

static void set_status(const char *status) {
  if (status_char) {
    status_char->setValue((uint8_t *)status, strlen(status));
    status_char->notify();
  }
  Serial.printf("[prov] status: %s\n", status);
}

static void strip_trailing(char *buf, size_t *len) {
  while (*len > 0 && (buf[*len - 1] == '\r' || buf[*len - 1] == '\n' || buf[*len - 1] == ' '))
    buf[--(*len)] = '\0';
}

class ProvisioningSsidCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    size_t len = c->getLength();
    if (len == 0 || len > 32) return;
    memcpy(prov_ssid, c->getData(), len);
    prov_ssid[len] = '\0';
    strip_trailing(prov_ssid, &len);
    Serial.printf("[prov] SSID received: %s\n", prov_ssid);
  }
};

class ProvisioningPasswordCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    size_t len = c->getLength();
    if (len > 64) return;
    memcpy(prov_pass, c->getData(), len);
    prov_pass[len] = '\0';
    strip_trailing(prov_pass, &len);
    Serial.println(F("[prov] password received"));

    if (prov_ssid[0] != '\0') {
      prov_credentials_received = true;
    }
  }
};

class ProvisioningConfigCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    uint8_t *data = c->getData();
    size_t len = c->getLength();
    if (!data || len == 0) return;

    JsonDocument doc;
    if (deserializeJson(doc, data, len) != DeserializationError::Ok) return;

    PreferencesGuard prefs(config::provisioning::NVS_NAMESPACE, false);
    for (JsonPair kv : doc.as<JsonObject>()) {
      const char *val = kv.value().as<const char *>();
      if (val) {
        prefs->putString(kv.key().c_str(), val);
        Serial.printf("[prov] config: %s=%s\n", kv.key().c_str(), val);
      }
    }
  }
};

class ProvisioningServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    Serial.println(F("[prov] client connected"));
    set_status("connected");
  }
  void onDisconnect(BLEServer *server) override {
    Serial.println(F("[prov] client disconnected"));
    if (!prov_done) {
      server->startAdvertising();
    }
  }
};

void boot::provisioning::start(void) {
  Serial.println(F("[prov] starting BLE provisioning"));
  Serial.printf("[prov] passkey: %d\n", config::ble::PASSKEY);

  prov_credentials_received = false;
  prov_done = false;
  prov_ssid[0] = '\0';
  prov_pass[0] = '\0';

  BLEDevice::init(config::HOSTNAME);

  BLESecurity *pSecurity = new BLESecurity();
  pSecurity->setPassKey(true, config::ble::PASSKEY);
  pSecurity->setCapability(ESP_IO_CAP_OUT);
  pSecurity->setAuthenticationMode(true, true, true);

  prov_server = BLEDevice::createServer();
  prov_server->setCallbacks(new ProvisioningServerCallbacks());
  prov_server->advertiseOnDisconnect(true);

  BLEService *svc = prov_server->createService(config::provisioning::SERVICE_UUID);

  BLECharacteristic *ssid_char = svc->createCharacteristic(
      PROV_CHAR_SSID_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_AUTHEN);
  ssid_char->setAccessPermissions(ESP_GATT_PERM_WRITE_ENC_MITM);
  ssid_char->setCallbacks(new ProvisioningSsidCallbacks());

  BLECharacteristic *pass_char = svc->createCharacteristic(
      PROV_CHAR_PASSWORD_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_AUTHEN);
  pass_char->setAccessPermissions(ESP_GATT_PERM_WRITE_ENC_MITM);
  pass_char->setCallbacks(new ProvisioningPasswordCallbacks());

  BLECharacteristic *config_char = svc->createCharacteristic(
      config::provisioning::CONFIG_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_AUTHEN);
  config_char->setAccessPermissions(ESP_GATT_PERM_WRITE_ENC_MITM);
  config_char->setCallbacks(new ProvisioningConfigCallbacks());

  status_char = svc->createCharacteristic(
      PROV_CHAR_STATUS_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
      | BLECharacteristic::PROPERTY_READ_AUTHEN);
  status_char->setAccessPermissions(ESP_GATT_PERM_READ_ENC_MITM);

  svc->start();
  set_status("waiting");

  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(config::provisioning::SERVICE_UUID);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();

  Serial.printf("[prov] advertising as '%s', waiting for credentials...\n", config::HOSTNAME);

  while (!prov_credentials_received) {
    delay(100);
  }

  set_status("connecting");

  WiFi.disconnect(true);
  WiFi.mode(WIFI_MODE_STA);
  WiFi.setHostname(config::HOSTNAME);
  WiFi.begin(prov_ssid, prov_pass);

  if (WiFi.waitForConnectResult(config::wifi::CONNECT_TIMEOUT_MS) == WL_CONNECTED) {
    set_status("connected_wifi");
    Serial.printf("[prov] WiFi connected, heap: %u bytes free\n", ESP.getFreeHeap());
  } else {
    set_status("failed");
    Serial.println(F("[prov] WiFi connection failed"));
  }

  delay(2000);
  prov_done = true;

  BLEDevice::deinit(true);
  status_char = nullptr;
  prov_server = nullptr;

  Serial.printf("[prov] BLE freed, heap: %u bytes free\n", ESP.getFreeHeap());
}

#else

void boot::provisioning::start(void) {}

#endif

// ─────────────────────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING


#include "provisioning.h"
#include "../testing/it.h"
#include "../testing/nvs_helpers.h"
#include "../config.h"

#include <Preferences.h>
#include <WiFi.h>
#include <esp_wifi.h>

static void provisioning_test_detects_provisioned_with_credentials(void) {
  TEST_MESSAGE("user verifies provisioning detection");

#if defined(CONFIG_WIFI_SSID) && defined(CONFIG_WIFI_PASS)
  if (strlen(CONFIG_WIFI_SSID) > 0) {
    TEST_ASSERT_TRUE_MESSAGE(boot::provisioning::isProvisioned(),
      "device: should be provisioned when build flags have SSID");
    TEST_MESSAGE("provisioned via build flags");
    return;
  }

#endif
}

static void provisioning_test_custom_config_roundtrip(void) {
  TEST_MESSAGE("user stores and retrieves custom config via NVS");

  char username[64] = {0};
  char api_key[64] = {0};
  char device_name[64] = {0};

  PreferencesGuard prefs(config::provisioning::NVS_NAMESPACE, false);
  TEST_ASSERT_TRUE_MESSAGE(prefs.ok(),
    "device: provisioning NVS namespace must be writable");

  prefs->putString("username", "alice");
  prefs->putString("api_key", "secret-key");
  prefs->putString("device_name", "ceratina-lab");

  TEST_ASSERT_TRUE_MESSAGE(boot::provisioning::accessUsername(username, sizeof(username)),
    "device: username should be readable after write");
  TEST_ASSERT_TRUE_MESSAGE(boot::provisioning::accessAPIKey(api_key, sizeof(api_key)),
    "device: api key should be readable after write");
  TEST_ASSERT_TRUE_MESSAGE(boot::provisioning::accessDeviceName(device_name, sizeof(device_name)),
    "device: device name should be readable after write");

  TEST_ASSERT_EQUAL_STRING_MESSAGE("alice", username,
    "device: username mismatch after roundtrip");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("secret-key", api_key,
    "device: api key mismatch after roundtrip");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("ceratina-lab", device_name,
    "device: device name mismatch after roundtrip");
}

static void provisioning_test_reset_clears_all(void) {
  TEST_MESSAGE("user resets provisioning and verifies cleanup");

  WifiNvsSnapshot wifi_snapshot = {};
  wifi_nvs_save(&wifi_snapshot);

  {
    PreferencesGuard prov_prefs(config::provisioning::NVS_NAMESPACE, false);
    TEST_ASSERT_TRUE_MESSAGE(prov_prefs.ok(),
      "device: provisioning NVS namespace must be writable");
    prov_prefs->putString("username", "bob");
    prov_prefs->putString("api_key", "temp-key");
    prov_prefs->putString("device_name", "temporary-device");
  }

  {
    PreferencesGuard wifi_prefs(config::wifi::NVS_NAMESPACE, false);
    TEST_ASSERT_TRUE_MESSAGE(wifi_prefs.ok(),
      "device: wifi NVS namespace must be writable");
    wifi_prefs->putString("ap_ssid", "test-ap");
    wifi_prefs->putString("ap_pass", "test-pass");
    wifi_prefs->putBool("ap_on", true);
  }

  boot::provisioning::reset();

  {
    PreferencesGuard prov_prefs(config::provisioning::NVS_NAMESPACE, true);
    TEST_ASSERT_TRUE_MESSAGE(prov_prefs.ok(),
      "device: provisioning NVS namespace must remain readable");
    TEST_ASSERT_FALSE_MESSAGE(prov_prefs->isKey("username"),
      "device: username should be cleared by reset");
    TEST_ASSERT_FALSE_MESSAGE(prov_prefs->isKey("api_key"),
      "device: api_key should be cleared by reset");
    TEST_ASSERT_FALSE_MESSAGE(prov_prefs->isKey("device_name"),
      "device: device_name should be cleared by reset");
  }

  {
    PreferencesGuard wifi_prefs(config::wifi::NVS_NAMESPACE, true);
    TEST_ASSERT_TRUE_MESSAGE(wifi_prefs.ok(),
      "device: wifi NVS namespace must remain readable");
    TEST_ASSERT_FALSE_MESSAGE(wifi_prefs->isKey("ap_ssid"),
      "device: AP SSID should be cleared by reset");
    TEST_ASSERT_FALSE_MESSAGE(wifi_prefs->isKey("ap_pass"),
      "device: AP password should be cleared by reset");
    TEST_ASSERT_FALSE_MESSAGE(wifi_prefs->isKey("ap_on"),
      "device: AP enabled flag should be cleared by reset");
  }

  wifi_nvs_restore(&wifi_snapshot);
}

static void provisioning_test_empty_config_returns_false(void) {
  TEST_MESSAGE("user reads config from empty NVS and gets false");

  {
    PreferencesGuard prefs(config::provisioning::NVS_NAMESPACE, false);
    TEST_ASSERT_TRUE_MESSAGE(prefs.ok(),
      "device: provisioning NVS namespace must be writable");
    prefs->clear();
  }

  char value[64] = {0};
  TEST_ASSERT_FALSE_MESSAGE(boot::provisioning::accessUsername(value, sizeof(value)),
    "device: missing username should return false");
  TEST_ASSERT_FALSE_MESSAGE(boot::provisioning::accessAPIKey(value, sizeof(value)),
    "device: missing api key should return false");
  TEST_ASSERT_FALSE_MESSAGE(boot::provisioning::accessDeviceName(value, sizeof(value)),
    "device: missing device name should return false");
}

static void provisioning_test_service_uuids_configured(void) {
  TEST_MESSAGE("user verifies BLE provisioning UUIDs are configured");

  TEST_ASSERT_NOT_NULL_MESSAGE(config::provisioning::SERVICE_UUID,
    "device: provisioning service UUID must be configured");
  TEST_ASSERT_NOT_NULL_MESSAGE(config::provisioning::CONFIG_UUID,
    "device: provisioning config UUID must be configured");
  TEST_ASSERT_GREATER_THAN_MESSAGE(0, (int)strlen(config::provisioning::SERVICE_UUID),
    "device: provisioning service UUID must not be empty");
  TEST_ASSERT_GREATER_THAN_MESSAGE(0, (int)strlen(config::provisioning::CONFIG_UUID),
    "device: provisioning config UUID must not be empty");
}

void boot::provisioning::test(void) {
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
