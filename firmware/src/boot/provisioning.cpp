#include "provisioning.h"
#include <config.h>
#include <identity.h>

#include <Arduino.h>
#include <Preferences.h>
#include <WiFi.h>
#include <atomic>
#include <esp_wifi.h>

namespace {

bool clear_namespace(const char *name_space) {
  Preferences prefs;
  if (!prefs.begin(name_space, false))
    return false;
  prefs.clear();
  prefs.end();
  return true;
}

bool open_namespace(const char *name_space, bool readonly, Preferences *prefs) {
  return prefs && prefs->begin(name_space, readonly);
}

} // namespace

bool boot::provisioning::isEnabled(void) { return CERATINA_PROV_ENABLED; }

bool boot::provisioning::isProvisioned(void) {
  wifi_config_t conf;
  if (esp_wifi_get_config(WIFI_IF_STA, &conf) == ESP_OK &&
      conf.sta.ssid[0] != '\0')
    return true;

#if defined(CONFIG_WIFI_SSID) && defined(CONFIG_WIFI_PASS)
  if (strlen(CONFIG_WIFI_SSID) > 0)
    return true;
#endif

  return false;
}

void boot::provisioning::reset(void) {
  clear_namespace(config::provisioning::NVS_NAMESPACE);
  clear_namespace(config::wifi::NVS_NAMESPACE);
  WiFi.disconnect(true, true); // erases ESP-IDF stored STA credentials
  Serial.println(F("[prov] reset — credentials cleared"));
}

#if CERATINA_PROV_ENABLED

#include <ArduinoJson.h>
#include <BLEDevice.h>
#include <BLESecurity.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <atomic>

#define PROV_CHAR_SSID_UUID "ceaa0002-b5a3-f393-e0a9-e50e24dcca9e"
#define PROV_CHAR_PASSWORD_UUID "ceaa0003-b5a3-f393-e0a9-e50e24dcca9e"
#define PROV_CHAR_STATUS_UUID "ceaa0004-b5a3-f393-e0a9-e50e24dcca9e"

static BLEServer *prov_server = nullptr;
static BLECharacteristic *status_char = nullptr;
static std::atomic<bool> prov_credentials_received = false;
static std::atomic<bool> prov_done = false;

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
  while (*len > 0 && (buf[*len - 1] == '\r' || buf[*len - 1] == '\n' ||
                      buf[*len - 1] == ' '))
    buf[--(*len)] = '\0';
}

class ProvisioningSsidCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    size_t len = c->getLength();
    if (len == 0 || len > 32)
      return;
    memcpy(prov_ssid, c->getData(), len);
    prov_ssid[len] = '\0';
    strip_trailing(prov_ssid, &len);
    Serial.printf("[prov] SSID received: %s\n", prov_ssid);
  }
};

class ProvisioningPasswordCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    size_t len = c->getLength();
    if (len > 64)
      return;
    memcpy(prov_pass, c->getData(), len);
    prov_pass[len] = '\0';
    strip_trailing(prov_pass, &len);
    Serial.println(F("[prov] password received"));

    if (prov_ssid[0] != '\0') {
      prov_credentials_received.store(true, std::memory_order_release);
    }
  }
};

class ProvisioningConfigCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    uint8_t *data = c->getData();
    size_t len = c->getLength();
    if (!data || len == 0)
      return;

    JsonDocument doc;
    if (deserializeJson(doc, data, len) != DeserializationError::Ok)
      return;

    Preferences prefs;
    if (!open_namespace(config::provisioning::NVS_NAMESPACE, false, &prefs))
      return;
    for (JsonPair kv : doc.as<JsonObject>()) {
      const char *val = kv.value().as<const char *>();
      if (val) {
        prefs.putString(kv.key().c_str(), val);
        Serial.printf("[prov] config: %s=%s\n", kv.key().c_str(), val);
      }
    }
    prefs.end();
  }
};

class ProvisioningServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    Serial.println(F("[prov] client connected"));
    set_status("connected");
  }
  void onDisconnect(BLEServer *server) override {
    Serial.println(F("[prov] client disconnected"));
    if (!prov_done.load(std::memory_order_acquire)) {
      server->startAdvertising();
    }
  }
};

void boot::provisioning::start(void) {
  Serial.println(F("[prov] starting BLE provisioning"));
  Serial.printf("[prov] passkey: %d\n", config::ble::PASSKEY);

  prov_credentials_received.store(false, std::memory_order_relaxed);
  prov_done.store(false, std::memory_order_relaxed);
  prov_ssid[0] = '\0';
  prov_pass[0] = '\0';

  BLEDevice::init(config::HOSTNAME);

  // Intentionally leaked — BLE stack owns these for device lifetime.
  BLESecurity *pSecurity = new BLESecurity();
  pSecurity->setPassKey(true, config::ble::PASSKEY);
  pSecurity->setCapability(ESP_IO_CAP_OUT);
  pSecurity->setAuthenticationMode(true, true, true);

  prov_server = BLEDevice::createServer();
  prov_server->setCallbacks(
      new ProvisioningServerCallbacks()); // BLE stack owns
  prov_server->advertiseOnDisconnect(true);

  BLEService *svc =
      prov_server->createService(config::provisioning::SERVICE_UUID);

  BLECharacteristic *ssid_char = svc->createCharacteristic(
      PROV_CHAR_SSID_UUID, BLECharacteristic::PROPERTY_WRITE |
                               BLECharacteristic::PROPERTY_WRITE_AUTHEN);
  ssid_char->setAccessPermissions(ESP_GATT_PERM_WRITE_ENC_MITM);
  ssid_char->setCallbacks(new ProvisioningSsidCallbacks()); // BLE stack owns

  BLECharacteristic *pass_char = svc->createCharacteristic(
      PROV_CHAR_PASSWORD_UUID, BLECharacteristic::PROPERTY_WRITE |
                                   BLECharacteristic::PROPERTY_WRITE_AUTHEN);
  pass_char->setAccessPermissions(ESP_GATT_PERM_WRITE_ENC_MITM);
  pass_char->setCallbacks(
      new ProvisioningPasswordCallbacks()); // BLE stack owns

  BLECharacteristic *config_char =
      svc->createCharacteristic(config::provisioning::CONFIG_UUID,
                                BLECharacteristic::PROPERTY_WRITE |
                                    BLECharacteristic::PROPERTY_WRITE_AUTHEN);
  config_char->setAccessPermissions(ESP_GATT_PERM_WRITE_ENC_MITM);
  config_char->setCallbacks(
      new ProvisioningConfigCallbacks()); // BLE stack owns

  status_char = svc->createCharacteristic(
      PROV_CHAR_STATUS_UUID, BLECharacteristic::PROPERTY_READ |
                                 BLECharacteristic::PROPERTY_NOTIFY |
                                 BLECharacteristic::PROPERTY_READ_AUTHEN);
  status_char->setAccessPermissions(ESP_GATT_PERM_READ_ENC_MITM);

  svc->start();
  set_status("waiting");

  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(config::provisioning::SERVICE_UUID);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();

  Serial.printf("[prov] advertising as '%s', waiting for credentials...\n",
                config::HOSTNAME);

  while (!prov_credentials_received.load(std::memory_order_acquire)) {
    delay(100);
  }

  set_status("connecting");

  WifiConnectCommand command = {
      .request =
          {
              .ssid = prov_ssid,
              .password = prov_pass,
              .enable_ap_fallback = false,
          },
      .result = {},
  };

  if (networking::wifi::connect(&command)) {
    set_status("connected_wifi");
    Serial.printf("[prov] WiFi connected, heap: %u bytes free\n",
                  ESP.getFreeHeap());
  } else {
    set_status("failed");
    Serial.println(F("[prov] WiFi connection failed"));
  }

  delay(2000);
  prov_done.store(true, std::memory_order_release);

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
#include <testing/utils.h>

#include <config.h>

#include <Preferences.h>
#include <WiFi.h>
#include <esp_wifi.h>

static bool test_open_namespace(const char *name_space, bool readonly,
                                Preferences *prefs) {
  return prefs && prefs->begin(name_space, readonly);
}

static void test_provisioning_detects_credentials(void) {
  GIVEN("build flags with WiFi credentials");
  THEN("provisioning state is detected");

#if defined(CONFIG_WIFI_SSID) && defined(CONFIG_WIFI_PASS)
  if (strlen(CONFIG_WIFI_SSID) > 0) {
    TEST_ASSERT_TRUE_MESSAGE(
        boot::provisioning::isProvisioned(),
        "device: should be provisioned when build flags have SSID");
    return;
  }

#endif
}

static void test_provisioning_config_roundtrip(void) {
  GIVEN("custom provisioning values written to NVS");
  WHEN("they are read back");

  char username[64] = {0};
  char api_key[64] = {0};
  char device_name[64] = {0};

  Preferences prefs;
  TEST_ASSERT_TRUE_MESSAGE(
      test_open_namespace(config::provisioning::NVS_NAMESPACE, false, &prefs),
      "device: provisioning NVS namespace must be writable");

  prefs.putString("username", "alice");
  prefs.putString("api_key", "secret-key");
  prefs.putString("device_name", "ceratina-lab");
  prefs.end();

  IdentityStringQuery username_query = {
      .buffer = username,
      .capacity = sizeof(username),
      .ok = false,
  };
  TEST_ASSERT_TRUE_MESSAGE(services::identity::access_username(&username_query),
                           "device: username should be readable after write");
  IdentityStringQuery api_key_query = {
      .buffer = api_key,
      .capacity = sizeof(api_key),
      .ok = false,
  };
  TEST_ASSERT_TRUE_MESSAGE(services::identity::accessAPIKey(&api_key_query),
                           "device: api key should be readable after write");
  IdentityStringQuery device_name_query = {
      .buffer = device_name,
      .capacity = sizeof(device_name),
      .ok = false,
  };
  TEST_ASSERT_TRUE_MESSAGE(
      services::identity::access_device_name(&device_name_query),
      "device: device name should be readable after write");

  TEST_ASSERT_EQUAL_STRING_MESSAGE("alice", username,
                                   "device: username mismatch after roundtrip");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("secret-key", api_key,
                                   "device: api key mismatch after roundtrip");
  TEST_ASSERT_EQUAL_STRING_MESSAGE(
      "ceratina-lab", device_name,
      "device: device name mismatch after roundtrip");
}

static void test_provisioning_reset_clears_all(void) {
  GIVEN("provisioning and WiFi NVS entries");
  WHEN("reset is called");

  WifiNvsSnapshot wifi_snapshot = {};
  wifi_nvs_save(&wifi_snapshot);

  {
    Preferences prov_prefs;
    TEST_ASSERT_TRUE_MESSAGE(
        test_open_namespace(config::provisioning::NVS_NAMESPACE, false,
                            &prov_prefs),
        "device: provisioning NVS namespace must be writable");
    prov_prefs.putString("username", "bob");
    prov_prefs.putString("api_key", "temp-key");
    prov_prefs.putString("device_name", "temporary-device");
    prov_prefs.end();
  }

  {
    Preferences wifi_prefs;
    TEST_ASSERT_TRUE_MESSAGE(
        test_open_namespace(config::wifi::NVS_NAMESPACE, false, &wifi_prefs),
        "device: wifi NVS namespace must be writable");
    wifi_prefs.putString("ap_ssid", "test-ap");
    wifi_prefs.putString("ap_pass", "test-pass");
    wifi_prefs.putBool("ap_on", true);
    wifi_prefs.end();
  }

  boot::provisioning::reset();

  {
    Preferences prov_prefs;
    TEST_ASSERT_TRUE_MESSAGE(
        test_open_namespace(config::provisioning::NVS_NAMESPACE, true,
                            &prov_prefs),
        "device: provisioning NVS namespace must remain readable");
    TEST_ASSERT_FALSE_MESSAGE(prov_prefs.isKey("username"),
                              "device: username should be cleared by reset");
    TEST_ASSERT_FALSE_MESSAGE(prov_prefs.isKey("api_key"),
                              "device: api_key should be cleared by reset");
    TEST_ASSERT_FALSE_MESSAGE(prov_prefs.isKey("device_name"),
                              "device: device_name should be cleared by reset");
    prov_prefs.end();
  }

  {
    Preferences wifi_prefs;
    TEST_ASSERT_TRUE_MESSAGE(
        test_open_namespace(config::wifi::NVS_NAMESPACE, true, &wifi_prefs),
        "device: wifi NVS namespace must remain readable");
    TEST_ASSERT_FALSE_MESSAGE(wifi_prefs.isKey("ap_ssid"),
                              "device: AP SSID should be cleared by reset");
    TEST_ASSERT_FALSE_MESSAGE(wifi_prefs.isKey("ap_pass"),
                              "device: AP password should be cleared by reset");
    TEST_ASSERT_FALSE_MESSAGE(
        wifi_prefs.isKey("ap_on"),
        "device: AP enabled flag should be cleared by reset");
    wifi_prefs.end();
  }

  wifi_nvs_restore(&wifi_snapshot);
}

static void test_provisioning_empty_returns_false(void) {
  GIVEN("a cleared NVS namespace");
  WHEN("identity fields are read");

  {
    Preferences prefs;
    TEST_ASSERT_TRUE_MESSAGE(
        test_open_namespace(config::provisioning::NVS_NAMESPACE, false, &prefs),
        "device: provisioning NVS namespace must be writable");
    prefs.clear();
    prefs.end();
  }

  char value[64] = {0};
  IdentityStringQuery query = {
      .buffer = value,
      .capacity = sizeof(value),
      .ok = false,
  };
  TEST_ASSERT_FALSE_MESSAGE(services::identity::access_username(&query),
                            "device: missing username should return false");
  TEST_ASSERT_FALSE_MESSAGE(services::identity::accessAPIKey(&query),
                            "device: missing api key should return false");
  TEST_ASSERT_FALSE_MESSAGE(services::identity::access_device_name(&query),
                            "device: missing device name should return false");
}

static void test_provisioning_uuids_configured(void) {
  GIVEN("BLE provisioning constants");
  THEN("UUIDs are configured and non-empty");

  TEST_ASSERT_NOT_NULL_MESSAGE(
      config::provisioning::SERVICE_UUID,
      "device: provisioning service UUID must be configured");
  TEST_ASSERT_NOT_NULL_MESSAGE(
      config::provisioning::CONFIG_UUID,
      "device: provisioning config UUID must be configured");
  TEST_ASSERT_NOT_EMPTY_MESSAGE(config::provisioning::SERVICE_UUID,
      "device: provisioning service UUID must not be empty");
  TEST_ASSERT_NOT_EMPTY_MESSAGE(config::provisioning::CONFIG_UUID,
      "device: provisioning config UUID must not be empty");
}

void boot::provisioning::test(void) {
  RUN_TEST(test_provisioning_detects_credentials);
  RUN_TEST(test_provisioning_config_roundtrip);
  RUN_TEST(test_provisioning_reset_clears_all);
  RUN_TEST(test_provisioning_empty_returns_false);
  RUN_TEST(test_provisioning_uuids_configured);
}

#endif
