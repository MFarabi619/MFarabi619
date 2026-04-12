#include "ble.h"
#include "../config.h"
#include "../programs/shell/shell.h"
#include "../programs/shell/session.h"
#include "../services/identity.h"
#include "../services/system.h"
#include "../sensors/manager.h"

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLESecurity.h>
#include <microshell.h>

// Nordic UART Service UUIDs (industry standard)
#define NUS_SERVICE_UUID   "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define NUS_RX_UUID        "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define NUS_TX_UUID        "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

// Sensor service UUIDs
#define SENSOR_SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define SENSOR_STATUS_UUID  "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define SENSOR_VOLTAGE_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a9"

static BLEServer *ble_server = nullptr;
static BLECharacteristic *nus_tx = nullptr;
static BLECharacteristic *nus_rx = nullptr;
static BLECharacteristic *sensor_status = nullptr;
static BLECharacteristic *sensor_voltage = nullptr;

static char ring_buf[config::ble::RING_SIZE];
static char write_buf[config::ble::WRITE_BUF];
static programs::shell::session::RingBuffer ring = {
  .data = ring_buf,
  .capacity = config::ble::RING_SIZE,
  .head = 0,
  .tail = 0,
};
static programs::shell::session::WriteBuffer write_state = {
  .data = write_buf,
  .capacity = config::ble::WRITE_BUF,
  .position = 0,
};

static void write_flush(void) {
  if (write_state.position == 0 || !nus_tx || networking::ble::clientCount() == 0) return;
  nus_tx->setValue((uint8_t *)write_buf, write_state.position);
  nus_tx->notify();
  programs::shell::session::reset(&write_state);
}

static int ble_shell_read(struct ush_object *self, char *ch) {
  (void)self;
  return programs::shell::session::pop(&ring, ch);
}

static int ble_shell_write(struct ush_object *self, char ch) {
  (void)self;
  if (networking::ble::clientCount() == 0) return 0;
  if (!programs::shell::session::push(&write_state, ch)) return 0;
  if (write_state.position >= config::ble::WRITE_BUF)
    write_flush();
  return 1;
}

static const struct ush_io_interface ble_shell_io = {
  .read = ble_shell_read,
  .write = ble_shell_write,
};

static char ble_in_buf[config::shell::BUF_IN];
static char ble_out_buf[config::shell::BUF_OUT];
static struct ush_object ble_ush;

static const struct ush_descriptor ble_shell_desc = {
  .io = &ble_shell_io,
  .input_buffer = ble_in_buf,
  .input_buffer_size = sizeof(ble_in_buf),
  .output_buffer = ble_out_buf,
  .output_buffer_size = sizeof(ble_out_buf),
  .path_max_length = config::shell::MAX_PATH_LEN,
  .hostname = const_cast<char *>(services::identity::accessHostname()),
};

class BleServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    uint32_t connected_clients = server->getConnectedCount();
    Serial.printf("[ble] client connected (%u total)\n", connected_clients);

    if (connected_clients == 1) {
      programs::shell::session::reset(&ring);
      programs::shell::session::reset(&write_state);
      programs::shell::initInstance(&ble_ush, &ble_shell_desc);
    }

    if (connected_clients < config::ble::MAX_CLIENTS) {
      BLEDevice::startAdvertising();
    } else {
      BLEDevice::stopAdvertising();
    }
  }

  void onDisconnect(BLEServer *server) override {
    uint32_t connected_clients = server->getConnectedCount();
    Serial.printf("[ble] client disconnected (%d remaining)\n", connected_clients);
  }
};

class BleRxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    String value = characteristic->getValue();
    for (size_t i = 0; i < value.length(); i++) {
      programs::shell::session::push(&ring, value[i]);
    }
  }
};

void networking::ble::initialize(void) {
  BLEDevice::init(config::HOSTNAME);
  BLEDevice::setMTU(517);

  BLESecurity *pSecurity = new BLESecurity();
  pSecurity->setPassKey(true, config::ble::PASSKEY);
  pSecurity->setCapability(ESP_IO_CAP_OUT);
  pSecurity->setAuthenticationMode(true, true, true);

  ble_server = BLEDevice::createServer();
  ble_server->setCallbacks(new BleServerCallbacks());
  ble_server->advertiseOnDisconnect(true);

  // Nordic UART Service
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
  nus_rx->setCallbacks(new BleRxCallbacks());

  nus->start();

  // Sensor service
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

  while (ush_service(&ble_ush)) {}
  write_flush();

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

// ─────────────────────────────────────────────────────────────────────────────
//  Tests — skipped by default (BLE stack uses ~50KB heap)
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING

#include "../testing/it.h"

// static void ble_test_init(void) {
//   TEST_MESSAGE("initializing BLE stack");
//   ble_init();
//   TEST_MESSAGE("BLE stack initialized and advertising");
// }
//
// static void ble_test_not_connected_initially(void) {
//   TEST_ASSERT_FALSE_MESSAGE(ble_is_connected(),
//     "device: should not have BLE clients on init");
//   TEST_ASSERT_EQUAL_INT_MESSAGE(0, ble_client_count(),
//     "device: client count should be 0");
//   TEST_MESSAGE("no clients connected after init");
// }
//
// static void ble_test_service_without_clients(void) {
//   TEST_MESSAGE("calling ble_service with no clients");
//   ble_service();
//   TEST_MESSAGE("ble_service returned without error");
// }

void networking::ble::test(void) {
  // BLE tests are skipped by default.
  // The NimBLE stack consumes ~50KB heap on init, which risks
  // exhausting memory when running alongside 70+ other tests.
  // Verify BLE by flashing and pairing with nRF Connect.
  //
  // To enable: uncomment the test functions above and the it() calls below.
  //
  // it("user initializes the BLE stack", ble_test_init);
  // it("user verifies no clients connected initially", ble_test_not_connected_initially);
  // it("user calls ble_service without clients", ble_test_service_without_clients);
}

#endif
