#include "ble.h"
#include <config.h>
#include "../console/remote.h"
#include <services/system.h>
#include <manager.h>

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLESecurity.h>

#define NUS_SERVICE_UUID   "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define NUS_RX_UUID        "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define NUS_TX_UUID        "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

#define SENSOR_SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define SENSOR_STATUS_UUID  "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define SENSOR_VOLTAGE_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a9"

//------------------------------------------
//  BLE transport
//------------------------------------------
static BLEServer *ble_server = nullptr;
static BLECharacteristic *nus_tx = nullptr;
static BLECharacteristic *nus_rx = nullptr;
static BLECharacteristic *sensor_status = nullptr;
static BLECharacteristic *sensor_voltage = nullptr;

static char ring_buf[config::ble::RING_SIZE];
static char wbuf[config::ble::WRITE_BUF];
static char line[config::shell::BUF_IN];

static void ble_flush(const char *data, size_t len, void *ctx) {
  (void)ctx;
  if (nus_tx && networking::ble::clientCount() > 0) {
    nus_tx->setValue((uint8_t *)data, len);
    nus_tx->notify();
  }
}

static console::remote::Shell shell(
  ring_buf, config::ble::RING_SIZE,
  wbuf, config::ble::WRITE_BUF,
  line, config::shell::BUF_IN,
  ble_flush, nullptr
);

//------------------------------------------
//  BLE callbacks
//------------------------------------------
class BleServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    uint32_t connected_clients = server->getConnectedCount();
    Serial.printf("[ble] client connected (%u total)\n", connected_clients);

    if (connected_clients == 1) {
      shell.reset();
      shell.send_prompt();
    }

    if (connected_clients < config::ble::MAX_CLIENTS)
      BLEDevice::startAdvertising();
    else
      BLEDevice::stopAdvertising();
  }

  void onDisconnect(BLEServer *server) override {
    uint32_t connected_clients = server->getConnectedCount();
    Serial.printf("[ble] client disconnected (%d remaining)\n", connected_clients);
  }
};

class BleRxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    String value = characteristic->getValue();
    shell.push_input(value.c_str(), value.length());
  }
};

//------------------------------------------
//  Public API
//------------------------------------------
void networking::ble::initialize(void) {
  BLEDevice::init(config::HOSTNAME);
  BLEDevice::setMTU(517);

  // Intentionally leaked — BLE stack owns these for device lifetime.
  BLESecurity *pSecurity = new BLESecurity();
  pSecurity->setPassKey(true, config::ble::PASSKEY);
  pSecurity->setCapability(ESP_IO_CAP_OUT);
  pSecurity->setAuthenticationMode(true, true, true);

  ble_server = BLEDevice::createServer();
  ble_server->setCallbacks(new BleServerCallbacks());  // BLE stack owns
  ble_server->advertiseOnDisconnect(true);

  BLEService *nus = ble_server->createService(NUS_SERVICE_UUID);

  nus_tx = nus->createCharacteristic(
    NUS_TX_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );

  nus_rx = nus->createCharacteristic(
    NUS_RX_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
    | BLECharacteristic::PROPERTY_WRITE_AUTHEN
  );
  nus_rx->setAccessPermissions(ESP_GATT_PERM_WRITE_ENC_MITM);
  nus_rx->setCallbacks(new BleRxCallbacks());  // BLE stack owns

  nus->start();

  BLEService *sensors = ble_server->createService(SENSOR_SERVICE_UUID);

  sensor_status = sensors->createCharacteristic(
    SENSOR_STATUS_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
    | BLECharacteristic::PROPERTY_READ_AUTHEN
  );
  sensor_status->setAccessPermissions(ESP_GATT_PERM_READ_ENC_MITM);

  sensor_voltage = sensors->createCharacteristic(
    SENSOR_VOLTAGE_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
    | BLECharacteristic::PROPERTY_READ_AUTHEN
  );
  sensor_voltage->setAccessPermissions(ESP_GATT_PERM_READ_ENC_MITM);

  sensors->start();

  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(NUS_SERVICE_UUID);
  advertising->addServiceUUID(SENSOR_SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  BLEDevice::startAdvertising();

  Serial.printf("[ble] advertising as %s (passkey: %u)\n",
                config::HOSTNAME, config::ble::PASSKEY);
}

static uint32_t last_sensor_notify = 0;

void networking::ble::service(void) {
  if (networking::ble::clientCount() == 0) return;

  shell.service();

  if (millis() - last_sensor_notify > 5000) {
    last_sensor_notify = millis();

    SystemQuery query = {
      .preferred_storage = StorageKind::LittleFS,
      .snapshot = {},
    };
    services::system::accessSnapshot(&query);
    char buf[64];
    snprintf(buf, sizeof(buf), "{\"heap\":%u,\"uptime\":%lu}",
             query.snapshot.heap_free, query.snapshot.uptime_seconds);
    sensor_status->setValue((uint8_t *)buf, strlen(buf));
    sensor_status->notify();

    VoltageSensorData sensor_data = {};
    if (sensors::manager::accessVoltage(&sensor_data)) {
      snprintf(buf, sizeof(buf), "[%.4f,%.4f,%.4f,%.4f]",
               sensor_data.channel_volts[0], sensor_data.channel_volts[1],
               sensor_data.channel_volts[2], sensor_data.channel_volts[3]);
      sensor_voltage->setValue((uint8_t *)buf, strlen(buf));
      sensor_voltage->notify();
    }
  }
}

bool networking::ble::isConnected(void) {
  return networking::ble::clientCount() > 0;
}

int networking::ble::clientCount(void) {
  return ble_server ? (int)ble_server->getConnectedCount() : 0;
}

#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

void networking::ble::test(void) {
}

#endif
