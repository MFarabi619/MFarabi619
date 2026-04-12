#include "i2c.h"
#include "../config.h"

#include <Arduino.h>
#include <Wire.h>

static bool power_enabled = false;

TCA9548 hardware::i2c::mux(config::i2c::MUX_ADDR, &Wire1);

void hardware::i2c::enable() noexcept {
  if (power_enabled) return;
  pinMode(config::i2c::RELAY_POWER_GPIO, OUTPUT);
  digitalWrite(config::i2c::RELAY_POWER_GPIO, HIGH);
  delay(100);
  power_enabled = true;
}

void hardware::i2c::disable() noexcept {
  if (!power_enabled) return;
  digitalWrite(config::i2c::RELAY_POWER_GPIO, LOW);
  power_enabled = false;
}

bool hardware::i2c::isEnabled() noexcept {
  return power_enabled;
}

bool hardware::i2c::initialize() noexcept {
  Wire.begin(config::i2c::BUS_0.sda_gpio, config::i2c::BUS_0.scl_gpio,
             config::i2c::FREQUENCY_KHZ * 1000);
  Wire.setTimeOut(100);

  Wire1.begin(config::i2c::BUS_1.sda_gpio, config::i2c::BUS_1.scl_gpio,
              config::i2c::FREQUENCY_KHZ * 1000);
  Wire1.setTimeOut(100);

  return mux.begin();
}

static inline int clamp(int pos, size_t limit) {
  return (pos >= (int)limit) ? (int)limit - 1 : pos;
}

bool hardware::i2c::scan(ScanCommand *command) noexcept {
  if (!command || !command->buffer || command->capacity == 0) return false;
  char *buf = command->buffer;
  size_t buf_size = command->capacity;
  int pos = 0;

  // Scan raw buses
  pos += snprintf(buf + pos, buf_size - pos, "bus 0:\r\n");
  for (uint8_t addr = config::i2c::ADDR_MIN; addr < config::i2c::ADDR_MAX && pos < (int)buf_size - 16; addr++) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      pos += snprintf(buf + pos, buf_size - pos, "  0x%02X\r\n", addr);
      pos = clamp(pos, buf_size);
    }
  }

  pos += snprintf(buf + pos, buf_size - pos, "bus 1:\r\n");
  for (uint8_t addr = config::i2c::ADDR_MIN; addr < config::i2c::ADDR_MAX && pos < (int)buf_size - 16; addr++) {
    Wire1.beginTransmission(addr);
    if (Wire1.endTransmission() == 0) {
      pos += snprintf(buf + pos, buf_size - pos, "  0x%02X\r\n", addr);
      pos = clamp(pos, buf_size);
    }
  }

  // Scan mux channels
  if (mux.isConnected()) {
    pos += snprintf(buf + pos, buf_size - pos, "mux:\r\n");
    pos = clamp(pos, buf_size);

    for (uint8_t ch = 0; ch < mux.channelCount() && pos < (int)buf_size - 32; ch++) {
      mux.selectChannel(ch);
      int found = 0;
      pos += snprintf(buf + pos, buf_size - pos, "  ch %d:", ch);
      pos = clamp(pos, buf_size);

      for (uint8_t addr = config::i2c::ADDR_MIN; addr < config::i2c::ADDR_MAX && pos < (int)buf_size - 16; addr++) {
        Wire1.beginTransmission(addr);
        if (Wire1.endTransmission() == 0) {
          pos += snprintf(buf + pos, buf_size - pos, " 0x%02X", addr);
          pos = clamp(pos, buf_size);
          found++;
        }
      }

      if (found == 0) {
        pos += snprintf(buf + pos, buf_size - pos, " (empty)");
        pos = clamp(pos, buf_size);
      }
      pos += snprintf(buf + pos, buf_size - pos, "\r\n");
      pos = clamp(pos, buf_size);
    }

    mux.disableAllChannels();
  }

  command->length = pos;
  return true;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING

#include "../testing/it.h"
#include "../testing/i2c_helpers.h"

static void i2c_mux_test_init(void) {
  test_ensure_wire1();
  TEST_MESSAGE("user asks the device to initialize the TCA9548A mux");
  TEST_ASSERT_TRUE_MESSAGE(hardware::i2c::mux.begin(),
    "device: mux.begin() failed — not responding at 0x70 on bus 1");
  TEST_MESSAGE("TCA9548A initialized on Wire1");
}

static void i2c_mux_test_is_connected(void) {
  TEST_MESSAGE("user checks if the mux is on the I2C bus");
  hardware::i2c::mux.begin();
  TEST_ASSERT_TRUE_MESSAGE(hardware::i2c::mux.isConnected(),
    "device: mux not found at 0x70");
  TEST_MESSAGE("mux is connected");
}

static void i2c_mux_test_channel_count(void) {
  TEST_MESSAGE("user verifies mux has 8 channels");
  hardware::i2c::mux.begin();
  TEST_ASSERT_EQUAL_UINT8_MESSAGE(8, hardware::i2c::mux.channelCount(),
    "device: TCA9548A should have 8 channels");
  TEST_MESSAGE("8 channels confirmed");
}

static void i2c_mux_test_select_and_verify(void) {
  TEST_MESSAGE("user selects channel 0 and verifies mask");
  hardware::i2c::mux.begin();

  TEST_ASSERT_TRUE_MESSAGE(hardware::i2c::mux.selectChannel(0),
    "device: selectChannel(0) failed");
  TEST_ASSERT_BIT_HIGH_MESSAGE(0, hardware::i2c::mux.getChannelMask(),
    "device: bit 0 should be high after select(0)");

  TEST_ASSERT_TRUE_MESSAGE(hardware::i2c::mux.selectChannel(3),
    "device: selectChannel(3) failed");
  TEST_ASSERT_BIT_HIGH_MESSAGE(3, hardware::i2c::mux.getChannelMask(),
    "device: bit 3 should be high after select(3)");
  TEST_ASSERT_BIT_LOW_MESSAGE(0, hardware::i2c::mux.getChannelMask(),
    "device: bit 0 should be low after select(3) — exclusive select");

  hardware::i2c::mux.disableAllChannels();
  TEST_MESSAGE("channel select and mask verified");
}

static void i2c_mux_test_scan(void) {
  TEST_MESSAGE("user scans all I2C buses and mux channels");
  hardware::i2c::mux.begin();

  char buf[1024];
  hardware::i2c::ScanCommand command = {
    .buffer = buf,
    .capacity = sizeof(buf),
    .length = 0,
  };
  TEST_ASSERT_TRUE_MESSAGE(hardware::i2c::scan(&command),
    "device: scan failed");
  TEST_ASSERT_GREATER_THAN_MESSAGE(0, command.length,
    "device: scan returned empty output");

  char *line = buf;
  for (char *cursor = buf; *cursor; cursor++) {
    if (*cursor == '\r' || *cursor == '\n') {
      *cursor = '\0';
      if (line[0] != '\0') TEST_MESSAGE(line);
      line = cursor + 1;
    }
  }
  if (line[0] != '\0') TEST_MESSAGE(line);
}

static void i2c_mux_test_disable_all_clears_mask(void) {
  TEST_MESSAGE("user enables channels then disables all");
  test_ensure_wire1();
  hardware::i2c::mux.begin();

  hardware::i2c::mux.enableChannel(0);
  hardware::i2c::mux.enableChannel(3);
  hardware::i2c::mux.enableChannel(7);
  TEST_ASSERT_NOT_EQUAL_HEX8_MESSAGE(0x00, hardware::i2c::mux.getChannelMask(),
    "device: mask should be non-zero after enabling channels");

  hardware::i2c::mux.disableAllChannels();
  TEST_ASSERT_EQUAL_HEX8_MESSAGE(0x00, hardware::i2c::mux.getChannelMask(),
    "device: mask should be 0x00 after disableAllChannels");

  TEST_MESSAGE("disable_all clears mask verified");
}

static void i2c_mux_test_enable_disable_roundtrip(void) {
  TEST_MESSAGE("user enables then disables a single channel");
  test_ensure_wire1();
  hardware::i2c::mux.begin();
  hardware::i2c::mux.disableAllChannels();

  hardware::i2c::mux.enableChannel(2);
  TEST_ASSERT_BIT_HIGH_MESSAGE(2, hardware::i2c::mux.getChannelMask(),
    "device: bit 2 should be high after enableChannel(2)");

  hardware::i2c::mux.disableChannel(2);
  TEST_ASSERT_BIT_LOW_MESSAGE(2, hardware::i2c::mux.getChannelMask(),
    "device: bit 2 should be low after disableChannel(2)");
  TEST_ASSERT_EQUAL_HEX8_MESSAGE(0x00, hardware::i2c::mux.getChannelMask(),
    "device: full mask should be 0x00 after disable");

  TEST_MESSAGE("enable/disable roundtrip verified");
}

void hardware::i2c::test() noexcept {
  it("user observes that the TCA9548A mux initializes",
     i2c_mux_test_init);
  it("user observes that the mux is connected at 0x70",
     i2c_mux_test_is_connected);
  it("user observes that the mux has 8 channels",
     i2c_mux_test_channel_count);
  it("user observes that channel selection updates the mask",
     i2c_mux_test_select_and_verify);
  it("user observes all I2C buses and mux devices via scan",
     i2c_mux_test_scan);
  it("user observes that disableAllChannels clears the mask",
     i2c_mux_test_disable_all_clears_mask);
  it("user observes that enable then disable roundtrips correctly",
     i2c_mux_test_enable_disable_roundtrip);
}

#endif
