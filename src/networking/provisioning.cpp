#include "provisioning.h"
#include "../config.h"
#include "wifi.h"

#include <Arduino.h>
#include <WiFi.h>
#include <Preferences.h>

#if CONFIG_PROV_ENABLED

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

class SsidCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    size_t len = c->getLength();
    if (len == 0 || len > 32) return;
    memcpy(prov_ssid, c->getData(), len);
    prov_ssid[len] = '\0';
    strip_trailing(prov_ssid, &len);
    Serial.printf("[prov] SSID received: %s\n", prov_ssid);
  }
};

class PasswordCallbacks : public BLECharacteristicCallbacks {
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

class ConfigCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    uint8_t *data = c->getData();
    size_t len = c->getLength();
    if (!data || len == 0) return;

    JsonDocument doc;
    if (deserializeJson(doc, data, len) != DeserializationError::Ok) return;

    Preferences prefs;
    prefs.begin(CONFIG_PROV_NVS_NAMESPACE, false);
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

class ProvServerCallbacks : public BLEServerCallbacks {
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

void provisioning_start(void) {
  Serial.println(F("[prov] starting BLE provisioning"));
  Serial.printf("[prov] passkey: %d\n", CONFIG_BLE_PASSKEY);

  prov_credentials_received = false;
  prov_done = false;
  prov_ssid[0] = '\0';
  prov_pass[0] = '\0';

  BLEDevice::init(CONFIG_HOSTNAME);

  BLESecurity *pSecurity = new BLESecurity();
  pSecurity->setPassKey(true, CONFIG_BLE_PASSKEY);
  pSecurity->setCapability(ESP_IO_CAP_OUT);
  pSecurity->setAuthenticationMode(true, true, true);

  prov_server = BLEDevice::createServer();
  prov_server->setCallbacks(new ProvServerCallbacks());
  prov_server->advertiseOnDisconnect(true);

  BLEService *svc = prov_server->createService(CONFIG_PROV_SERVICE_UUID);

  BLECharacteristic *ssid_char = svc->createCharacteristic(
      PROV_CHAR_SSID_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_AUTHEN);
  ssid_char->setAccessPermissions(ESP_GATT_PERM_WRITE_ENC_MITM);
  ssid_char->setCallbacks(new SsidCallbacks());

  BLECharacteristic *pass_char = svc->createCharacteristic(
      PROV_CHAR_PASSWORD_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_AUTHEN);
  pass_char->setAccessPermissions(ESP_GATT_PERM_WRITE_ENC_MITM);
  pass_char->setCallbacks(new PasswordCallbacks());

  BLECharacteristic *config_char = svc->createCharacteristic(
      CONFIG_PROV_CONFIG_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_AUTHEN);
  config_char->setAccessPermissions(ESP_GATT_PERM_WRITE_ENC_MITM);
  config_char->setCallbacks(new ConfigCallbacks());

  status_char = svc->createCharacteristic(
      PROV_CHAR_STATUS_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
      | BLECharacteristic::PROPERTY_READ_AUTHEN);
  status_char->setAccessPermissions(ESP_GATT_PERM_READ_ENC_MITM);

  svc->start();
  set_status("waiting");

  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(CONFIG_PROV_SERVICE_UUID);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();

  Serial.printf("[prov] advertising as '%s', waiting for credentials...\n", CONFIG_HOSTNAME);

  while (!prov_credentials_received) {
    delay(100);
  }

  set_status("connecting");
  wifi_set_credentials(prov_ssid, prov_pass);

  if (wifi_connect()) {
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

bool provisioning_is_provisioned(void) {
  char ssid[CONFIG_WIFI_SSID_IEEE_802_11_MAX_LENGTH + 1] = {0};
  if (wifi_get_ssid(ssid, sizeof(ssid)) && ssid[0] != '\0') return true;

#if defined(CONFIG_WIFI_SSID) && defined(CONFIG_WIFI_PASS)
  if (strlen(CONFIG_WIFI_SSID) > 0) return true;
#endif

  return false;
}

void provisioning_reset(void) {
  Preferences prefs;
  prefs.begin(CONFIG_PROV_NVS_NAMESPACE, false);
  prefs.clear();
  prefs.end();

  Preferences wifi_prefs;
  wifi_prefs.begin(CONFIG_WIFI_NVS_NAMESPACE, false);
  wifi_prefs.clear();
  wifi_prefs.end();

  WiFi.disconnect(true, true);
  Serial.println(F("[prov] reset — credentials cleared"));
}

static bool get_prov_string(const char *key, char *buf, size_t len) {
  Preferences prefs;
  prefs.begin(CONFIG_PROV_NVS_NAMESPACE, true);
  size_t n = prefs.getString(key, buf, len);
  prefs.end();
  return n > 0;
}

bool provisioning_get_username(char *buf, size_t len) {
  return get_prov_string("username", buf, len);
}

bool provisioning_get_api_key(char *buf, size_t len) {
  return get_prov_string("api_key", buf, len);
}

bool provisioning_get_device_name(char *buf, size_t len) {
  return get_prov_string("device_name", buf, len);
}

#else

void provisioning_start(void) {}
bool provisioning_is_provisioned(void) { return true; }
void provisioning_reset(void) {}
bool provisioning_get_username(char *buf, size_t len) { (void)buf; (void)len; return false; }
bool provisioning_get_api_key(char *buf, size_t len) { (void)buf; (void)len; return false; }
bool provisioning_get_device_name(char *buf, size_t len) { (void)buf; (void)len; return false; }

#endif
