#include "ble.h"
#include "../config.h"
#include "../programs/shell/shell.h"
#include "../drivers/ads1115.h"

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
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
static int connected_clients = 0;

static volatile uint16_t ring_head = 0;
static volatile uint16_t ring_tail = 0;
static char ring_buf[CONFIG_BLE_RING_SIZE];
static char write_buf[CONFIG_BLE_WRITE_BUF];
static size_t write_buf_pos = 0;

static void ring_reset(void) { ring_head = 0; ring_tail = 0; }

static bool ring_push(char ch) {
  uint16_t next = (ring_head + 1) % CONFIG_BLE_RING_SIZE;
  if (next == ring_tail) return false;
  ring_buf[ring_head] = ch;
  ring_head = next;
  return true;
}

static int ring_pop(char *ch) {
  if (ring_head == ring_tail) return 0;
  *ch = ring_buf[ring_tail];
  ring_tail = (ring_tail + 1) % CONFIG_BLE_RING_SIZE;
  return 1;
}

static void write_flush(void) {
  if (write_buf_pos == 0 || !nus_tx || connected_clients == 0) return;
  nus_tx->setValue((uint8_t *)write_buf, write_buf_pos);
  nus_tx->notify();
  write_buf_pos = 0;
}

static int ble_shell_read(struct ush_object *self, char *ch) {
  (void)self;
  return ring_pop(ch);
}

static int ble_shell_write(struct ush_object *self, char ch) {
  (void)self;
  if (connected_clients == 0) return 0;
  write_buf[write_buf_pos++] = ch;
  if (write_buf_pos >= CONFIG_BLE_WRITE_BUF)
    write_flush();
  return 1;
}

static const struct ush_io_interface ble_shell_io = {
  .read = ble_shell_read,
  .write = ble_shell_write,
};

static char ble_in_buf[CONFIG_SHELL_BUF_IN];
static char ble_out_buf[CONFIG_SHELL_BUF_OUT];
static struct ush_object ble_ush;

static const struct ush_descriptor ble_shell_desc = {
  .io = &ble_shell_io,
  .input_buffer = ble_in_buf,
  .input_buffer_size = sizeof(ble_in_buf),
  .output_buffer = ble_out_buf,
  .output_buffer_size = sizeof(ble_out_buf),
  .path_max_length = CONFIG_SHELL_PATH_MAX,
  .hostname = shell_get_hostname(),
};

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    connected_clients++;
    Serial.printf("[ble] client connected (%d total)\n", connected_clients);

    if (connected_clients == 1) {
      ring_reset();
      write_buf_pos = 0;
      shell_init_instance(&ble_ush, &ble_shell_desc);
    }

    if (connected_clients < CONFIG_BLE_MAX_CLIENTS) {
      BLEDevice::startAdvertising();
    }
  }

  void onDisconnect(BLEServer *server) override {
    connected_clients--;
    Serial.printf("[ble] client disconnected (%d remaining)\n", connected_clients);
    BLEDevice::startAdvertising();
  }
};

class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    String value = characteristic->getValue();
    for (size_t i = 0; i < value.length(); i++) {
      ring_push(value[i]);
    }
  }
};

void ble_init(void) {
  BLEDevice::init(CONFIG_HOSTNAME);
  BLEDevice::setMTU(517);

  BLESecurity *security = new BLESecurity();
  security->setStaticPIN(CONFIG_BLE_PASSKEY);
  security->setCapability(ESP_IO_CAP_OUT);
  security->setAuthenticationMode(ESP_LE_AUTH_REQ_SC_MITM_BOND);

  ble_server = BLEDevice::createServer();
  ble_server->setCallbacks(new ServerCallbacks());

  // Nordic UART Service
  BLEService *nus = ble_server->createService(NUS_SERVICE_UUID);

  nus_tx = nus->createCharacteristic(
    NUS_TX_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  nus_tx->addDescriptor(new BLE2902());

  nus_rx = nus->createCharacteristic(
    NUS_RX_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  nus_rx->setCallbacks(new RxCallbacks());

  nus->start();

  // Sensor service
  BLEService *sensors = ble_server->createService(SENSOR_SERVICE_UUID);

  sensor_status = sensors->createCharacteristic(
    SENSOR_STATUS_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  sensor_status->addDescriptor(new BLE2902());

  sensor_voltage = sensors->createCharacteristic(
    SENSOR_VOLTAGE_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  sensor_voltage->addDescriptor(new BLE2902());

  sensors->start();

  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(NUS_SERVICE_UUID);
  advertising->addServiceUUID(SENSOR_SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  BLEDevice::startAdvertising();

  Serial.printf("[ble] advertising as %s (passkey: %u)\n",
                CONFIG_HOSTNAME, CONFIG_BLE_PASSKEY);
}

static uint32_t last_sensor_notify = 0;

void ble_service(void) {
  if (connected_clients == 0) return;

  while (ush_service(&ble_ush)) {}
  write_flush();

  if (millis() - last_sensor_notify > 5000) {
    last_sensor_notify = millis();

    char buf[64];
    snprintf(buf, sizeof(buf), "{\"heap\":%u,\"uptime\":%lu}",
             ESP.getFreeHeap(), millis() / 1000);
    sensor_status->setValue((uint8_t *)buf, strlen(buf));
    sensor_status->notify();

    float volts[CONFIG_VOLTAGE_MONITOR_CHANNEL_COUNT];
    if (ads1115_read(volts, CONFIG_VOLTAGE_MONITOR_CHANNEL_COUNT)) {
      snprintf(buf, sizeof(buf), "[%.4f,%.4f,%.4f,%.4f]",
               volts[0], volts[1], volts[2], volts[3]);
      sensor_voltage->setValue((uint8_t *)buf, strlen(buf));
      sensor_voltage->notify();
    }
  }
}

bool ble_is_connected(void) {
  return connected_clients > 0;
}

int ble_client_count(void) {
  return connected_clients;
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

void ble_run_tests(void) {
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
