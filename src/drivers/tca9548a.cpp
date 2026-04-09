#include "tca9548a.h"
#include "../config.h"

#include <Arduino.h>
#include <Wire.h>
#include <TCA9548.h>

static TCA9548 mux(CONFIG_I2C_MUX_ADDR, &Wire1);

bool tca9548a_init(void) {
  return mux.begin();
}

bool tca9548a_is_connected(void) {
  return mux.isConnected();
}

uint8_t tca9548a_channel_count(void) {
  return mux.channelCount();
}

bool tca9548a_select(uint8_t channel) {
  return mux.selectChannel(channel);
}

bool tca9548a_enable(uint8_t channel) {
  return mux.enableChannel(channel);
}

bool tca9548a_disable(uint8_t channel) {
  return mux.disableChannel(channel);
}

bool tca9548a_disable_all(void) {
  return mux.disableAllChannels();
}

bool tca9548a_is_enabled(uint8_t channel) {
  return mux.isEnabled(channel);
}

uint8_t tca9548a_get_mask(void) {
  return mux.getChannelMask();
}

uint8_t tca9548a_find(uint8_t addr) {
  return mux.find(addr);
}

int tca9548a_scan_all(char *buf, size_t buf_size) {
  int pos = 0;

  for (uint8_t ch = 0; ch < mux.channelCount() && pos < (int)buf_size - 32; ch++) {
    mux.selectChannel(ch);
    int found = 0;
    pos += snprintf(buf + pos, buf_size - pos, "ch %d:", ch);

    for (uint8_t addr = CONFIG_I2C_ADDR_MIN; addr < CONFIG_I2C_ADDR_MAX && pos < (int)buf_size - 16; addr++) {
      Wire1.beginTransmission(addr);
      if (Wire1.endTransmission() == 0) {
        pos += snprintf(buf + pos, buf_size - pos, " 0x%02X", addr);
        found++;
      }
    }

    if (found == 0)
      pos += snprintf(buf + pos, buf_size - pos, " (empty)");
    pos += snprintf(buf + pos, buf_size - pos, "\r\n");
  }

  mux.disableAllChannels();
  return pos;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tests — describe("TCA9548A I2C Mux")
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING

#include "../testing/it.h"

static void ensure_wire1(void) {
  Wire1.begin(CONFIG_I2C_1_SDA_GPIO, CONFIG_I2C_1_SCL_GPIO,
              CONFIG_I2C_FREQUENCY_KHZ * 1000);
  Wire1.setTimeOut(100);
}

static void tca9548a_test_init(void) {
  ensure_wire1();
  TEST_MESSAGE("user asks the device to initialize the TCA9548A mux");
  TEST_ASSERT_TRUE_MESSAGE(tca9548a_init(),
    "device: tca9548a_init() failed — mux not responding at 0x70 on bus 1");
  TEST_MESSAGE("TCA9548A initialized on Wire1");
}

static void tca9548a_test_is_connected(void) {
  TEST_MESSAGE("user checks if the mux is on the I2C bus");
  tca9548a_init();
  TEST_ASSERT_TRUE_MESSAGE(tca9548a_is_connected(),
    "device: mux not found at 0x70");
  TEST_MESSAGE("mux is connected");
}

static void tca9548a_test_channel_count(void) {
  TEST_MESSAGE("user verifies mux has 8 channels");
  tca9548a_init();
  TEST_ASSERT_EQUAL_UINT8_MESSAGE(8, tca9548a_channel_count(),
    "device: TCA9548A should have 8 channels");
  TEST_MESSAGE("8 channels confirmed");
}

static void tca9548a_test_select_and_verify(void) {
  TEST_MESSAGE("user selects channel 0 and verifies mask");
  tca9548a_init();

  TEST_ASSERT_TRUE_MESSAGE(tca9548a_select(0),
    "device: selectChannel(0) failed");
  TEST_ASSERT_TRUE_MESSAGE(tca9548a_is_enabled(0),
    "device: channel 0 should be enabled after select");
  TEST_ASSERT_EQUAL_HEX8_MESSAGE(0x01, tca9548a_get_mask(),
    "device: mask should be 0x01 after selecting channel 0");

  TEST_ASSERT_TRUE_MESSAGE(tca9548a_select(3),
    "device: selectChannel(3) failed");
  TEST_ASSERT_EQUAL_HEX8_MESSAGE(0x08, tca9548a_get_mask(),
    "device: mask should be 0x08 after selecting channel 3");
  TEST_ASSERT_FALSE_MESSAGE(tca9548a_is_enabled(0),
    "device: channel 0 should be disabled after selecting channel 3");

  tca9548a_disable_all();
  TEST_MESSAGE("channel select and mask verified");
}

static void tca9548a_test_scan_finds_devices(void) {
  TEST_MESSAGE("user scans all mux channels for devices");
  tca9548a_init();

  char buf[1024];
  int len = tca9548a_scan_all(buf, sizeof(buf));
  TEST_ASSERT_GREATER_THAN_MESSAGE(0, len,
    "device: scan returned empty output");

  TEST_MESSAGE(buf);
}

void tca9548a_run_tests(void) {
  it("user observes that the TCA9548A mux initializes",
     tca9548a_test_init);
  it("user observes that the mux is connected at 0x70",
     tca9548a_test_is_connected);
  it("user observes that the mux has 8 channels",
     tca9548a_test_channel_count);
  it("user observes that channel selection updates the mask",
     tca9548a_test_select_and_verify);
  it("user observes devices behind the mux channels",
     tca9548a_test_scan_finds_devices);
}

#endif
