#include "eeprom.h"
#include "../config.h"

#include <Arduino.h>
#include <Wire.h>

AT24C32 filesystems::eeprom::IC(config::eeprom::I2C_ADDR, Wire1);

using filesystems::eeprom::IC;

bool filesystems::eeprom::initialize() noexcept {
  IC.read(0);
  return IC.getLastError() == 0;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING

#include "../testing/it.h"
#include "../testing/i2c_helpers.h"

#define TEST_BASE 3900

static void eeprom_test_init(void) {
  test_ensure_wire1();
  TEST_MESSAGE("user asks the device to detect the EEPROM");
  TEST_ASSERT_TRUE_MESSAGE(filesystems::eeprom::initialize(),
    "device: EEPROM not detected on bus 1");
  char msg[48];
  snprintf(msg, sizeof(msg), "EEPROM detected, size=%u bytes", IC.length());
  TEST_MESSAGE(msg);
}

static void eeprom_test_write_read_byte(void) {
  TEST_MESSAGE("user writes and reads a byte");
  filesystems::eeprom::initialize();
  IC.write(TEST_BASE, 0xAB);
  TEST_ASSERT_EQUAL_HEX8_MESSAGE(0xAB, IC.read(TEST_BASE),
    "device: byte mismatch");
  IC.write(TEST_BASE, 0x00);
  TEST_MESSAGE("byte roundtrip verified");
}

static void eeprom_test_put_get_struct(void) {
  TEST_MESSAGE("user writes and reads a struct via put/get");
  filesystems::eeprom::initialize();

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
  TEST_MESSAGE("struct roundtrip verified");
}

static void eeprom_test_buffer_roundtrip(void) {
  TEST_MESSAGE("user writes and reads a buffer");
  filesystems::eeprom::initialize();

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
  TEST_MESSAGE("buffer roundtrip verified");
}

static void eeprom_test_update_skips_same(void) {
  TEST_MESSAGE("user verifies update only writes if value differs");
  filesystems::eeprom::initialize();

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
  TEST_MESSAGE("update wear-reduction verified");
}

static void eeprom_test_last_byte(void) {
  TEST_MESSAGE("user writes and reads the last byte of EEPROM");
  filesystems::eeprom::initialize();

  uint16_t last = config::eeprom::TOTAL_SIZE - 1;
  IC.write(last, 0x77);
  TEST_ASSERT_EQUAL_HEX8_MESSAGE(0x77, IC.read(last),
    "device: last byte mismatch");
  TEST_ASSERT_EQUAL_UINT8_MESSAGE(0, IC.getLastError(),
    "device: error on last byte access");
  IC.write(last, 0x00);
  TEST_MESSAGE("last byte roundtrip verified");
}

static void eeprom_test_page_boundary_buffer(void) {
  TEST_MESSAGE("user writes a buffer that crosses a page boundary");
  filesystems::eeprom::initialize();

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
  TEST_MESSAGE("page boundary buffer verified");
}

void filesystems::eeprom::test() noexcept {
  it("user observes that the EEPROM is detected",
     eeprom_test_init);
  it("user observes that byte write/read roundtrips correctly",
     eeprom_test_write_read_byte);
  it("user observes that struct put/get roundtrips correctly",
     eeprom_test_put_get_struct);
  it("user observes that buffer write/read roundtrips correctly",
     eeprom_test_buffer_roundtrip);
  it("user observes that update skips writes when value unchanged",
     eeprom_test_update_skips_same);
  it("user observes that the last EEPROM byte is accessible",
     eeprom_test_last_byte);
  it("user observes that buffers crossing page boundaries work",
     eeprom_test_page_boundary_buffer);
}

#endif
