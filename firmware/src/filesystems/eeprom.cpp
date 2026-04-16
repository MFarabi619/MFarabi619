#include "eeprom.h"
#include <config.h>
#include <i2c.h>

#include <Arduino.h>

AT24C32 filesystems::eeprom::IC(config::eeprom::I2C_ADDR, Wire1);

using filesystems::eeprom::IC;

bool filesystems::eeprom::initialize() {
  config::I2CSensorConfig sensor_config = {config::I2CSensorKind::EEPROM_AT24C32, 1, config::eeprom::I2C_ADDR, config::i2c::DIRECT_CHANNEL};
  bool found = false;
  for (size_t index = 0; index < config::i2c_topology::DEVICE_COUNT; index++) {
    const config::I2CSensorConfig &candidate = config::i2c_topology::DEVICES[index];
    if (candidate.kind == config::I2CSensorKind::EEPROM_AT24C32) {
      sensor_config = candidate;
      found = true;
      break;
    }
  }
  if (!found) return false;

  hardware::i2c::DeviceAccessCommand command = {
    .bus = sensor_config.bus == 0 ? hardware::i2c::Bus::Bus0 : hardware::i2c::Bus::Bus1,
    .mux_channel = sensor_config.mux_channel,
    .wire = nullptr,
    .ok = false,
  };
  if (!hardware::i2c::accessDevice(&command)) return false;

  filesystems::eeprom::IC = AT24C32(sensor_config.address, *command.wire);
  IC.read(0);
  hardware::i2c::clearSelection();
  return IC.getLastError() == 0;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>


#define TEST_BASE 3900

static void test_eeprom_init(void) {
  GIVEN("Wire1 is available");
  test_ensure_wire1();
  hardware::i2c::initialize();

  WHEN("the EEPROM is detected");
  TEST_ASSERT_TRUE_MESSAGE(filesystems::eeprom::initialize(),
    "device: EEPROM not detected on bus 1");
  char msg[48];
  snprintf(msg, sizeof(msg), "EEPROM detected, size=%u bytes", IC.length());
  TEST_MESSAGE(msg);
}

static void test_eeprom_write_read_byte(void) {
  GIVEN("the EEPROM is initialized");
  filesystems::eeprom::initialize();

  WHEN("a byte is written and read back");
  IC.write(TEST_BASE, 0xAB);
  TEST_ASSERT_EQUAL_HEX8_MESSAGE(0xAB, IC.read(TEST_BASE),
    "device: byte mismatch");
  IC.write(TEST_BASE, 0x00);
}

static void test_eeprom_put_get_struct(void) {
  GIVEN("the EEPROM is initialized");
  filesystems::eeprom::initialize();

  WHEN("a struct is written and read back via put/get");

  struct { uint16_t co2; float temp; } reading = { 415, 23.5f };
  IC.put(TEST_BASE, reading);

  struct { uint16_t co2; float temp; } readback = {0, 0.0f};
  IC.get(TEST_BASE, readback);

  TEST_ASSERT_EQUAL_UINT16_MESSAGE(415, readback.co2,
    "device: co2 mismatch in struct");
  TEST_ASSERT_FLOAT_WITHIN_MESSAGE(0.01f, 23.5f, readback.temp,
    "device: temp mismatch in struct");

  struct { uint16_t co2; float temp; } zeros = {0, 0.0f};
  IC.put(TEST_BASE, zeros);
}

static void test_eeprom_buffer_roundtrip(void) {
  GIVEN("the EEPROM is initialized");
  filesystems::eeprom::initialize();

  WHEN("a buffer is written and read back");

  uint8_t write_buf[16];
  for (int i = 0; i < 16; i++) write_buf[i] = i + 0x10;

  IC.writeBuffer(TEST_BASE + 20, write_buf, 16);
  TEST_ASSERT_EQUAL_UINT8_MESSAGE(0, IC.getLastError(),
    "device: error on writeBuffer");

  uint8_t read_buf[16] = {0};
  IC.readBuffer(TEST_BASE + 20, read_buf, 16);

  TEST_ASSERT_EQUAL_HEX8_ARRAY_MESSAGE(write_buf, read_buf, 16,
    "device: buffer mismatch");

  uint8_t zeros[16] = {0};
  IC.writeBuffer(TEST_BASE + 20, zeros, 16);
}

static void test_eeprom_update_skips_same(void) {
  GIVEN("the EEPROM is initialized");
  filesystems::eeprom::initialize();

  WHEN("update is called with the same value");

  IC.write(TEST_BASE + 40, 0x42);
  IC.update(TEST_BASE + 40, 0x42);
  TEST_ASSERT_EQUAL_UINT8_MESSAGE(0, IC.getLastError(),
    "device: error on update with same value");
  TEST_ASSERT_EQUAL_HEX8_MESSAGE(0x42, IC.read(TEST_BASE + 40),
    "device: value changed after no-op update");

  IC.update(TEST_BASE + 40, 0x99);
  TEST_ASSERT_EQUAL_HEX8_MESSAGE(0x99, IC.read(TEST_BASE + 40),
    "device: value not changed after real update");

  IC.write(TEST_BASE + 40, 0x00);
}

static void test_eeprom_last_byte(void) {
  GIVEN("the EEPROM is initialized");
  filesystems::eeprom::initialize();

  WHEN("the last byte is written and read back");

  uint16_t last = config::eeprom::TOTAL_SIZE - 1;
  IC.write(last, 0x77);
  TEST_ASSERT_EQUAL_HEX8_MESSAGE(0x77, IC.read(last),
    "device: last byte mismatch");
  TEST_ASSERT_EQUAL_UINT8_MESSAGE(0, IC.getLastError(),
    "device: error on last byte access");
  IC.write(last, 0x00);
}

static void test_eeprom_page_boundary_buffer(void) {
  GIVEN("the EEPROM is initialized");
  filesystems::eeprom::initialize();

  WHEN("a buffer crossing a page boundary is written and read back");

  uint16_t addr = config::eeprom::PAGE_SIZE - 4;
  uint8_t write_buf[8] = {0xA0, 0xA1, 0xA2, 0xA3, 0xB0, 0xB1, 0xB2, 0xB3};
  IC.writeBuffer(addr, write_buf, 8);
  TEST_ASSERT_EQUAL_UINT8_MESSAGE(0, IC.getLastError(),
    "device: error on cross-page write");

  uint8_t read_buf[8] = {0};
  IC.readBuffer(addr, read_buf, 8);
  TEST_ASSERT_EQUAL_HEX8_ARRAY_MESSAGE(write_buf, read_buf, 8,
    "device: cross-page buffer mismatch");

  uint8_t zeros[8] = {0};
  IC.writeBuffer(addr, zeros, 8);
}

void filesystems::eeprom::test() {
  RUN_TEST(test_eeprom_init);
  RUN_TEST(test_eeprom_write_read_byte);
  RUN_TEST(test_eeprom_put_get_struct);
  RUN_TEST(test_eeprom_buffer_roundtrip);
  RUN_TEST(test_eeprom_update_skips_same);
  RUN_TEST(test_eeprom_last_byte);
  RUN_TEST(test_eeprom_page_boundary_buffer);
}

#endif
