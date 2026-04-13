#include "i2c.h"
#include "../config.h"

#include <Arduino.h>
#include <Wire.h>

static bool legacy_power_enabled = false;
static bool mux_present = false;
static bool mux_odd_power_enabled = false;
static bool mux_even_power_enabled = false;

TCA9548 hardware::i2c::mux(config::i2c::MUX_ADDR, &Wire1);

namespace {

void disable_legacy_power_rail(void) {
  if (!legacy_power_enabled) return;
  digitalWrite(config::i2c::LEGACY_POWER_GPIO, LOW);
  legacy_power_enabled = false;
}

void enable_legacy_power_rail(void) {
  if (legacy_power_enabled) return;
  pinMode(config::i2c::LEGACY_POWER_GPIO, OUTPUT);
  digitalWrite(config::i2c::LEGACY_POWER_GPIO, HIGH);
  delay(100);
  legacy_power_enabled = true;
}

void disable_mux_power_rails(void) {
  pinMode(config::i2c::MUX_POWER_GPIO_ODD, OUTPUT);
  pinMode(config::i2c::MUX_POWER_GPIO_EVEN, OUTPUT);
  digitalWrite(config::i2c::MUX_POWER_GPIO_ODD, LOW);
  digitalWrite(config::i2c::MUX_POWER_GPIO_EVEN, LOW);
  mux_odd_power_enabled = false;
  mux_even_power_enabled = false;
}

void enable_mux_power_for_channel(int8_t mux_channel) {
  // New board routing is fixed and intentionally spelled out here:
  //   channels 0,2,4,6 -> GPIO 6
  //   channels 1,3,5,7 -> GPIO 1
  switch (mux_channel) {
    case 0:
    case 2:
    case 4:
    case 6:
      pinMode(config::i2c::MUX_POWER_GPIO_EVEN, OUTPUT);
      digitalWrite(config::i2c::MUX_POWER_GPIO_EVEN, HIGH);
      digitalWrite(config::i2c::MUX_POWER_GPIO_ODD, LOW);
      mux_even_power_enabled = true;
      mux_odd_power_enabled = false;
      break;

    case 1:
    case 3:
    case 5:
    case 7:
      pinMode(config::i2c::MUX_POWER_GPIO_ODD, OUTPUT);
      digitalWrite(config::i2c::MUX_POWER_GPIO_ODD, HIGH);
      digitalWrite(config::i2c::MUX_POWER_GPIO_EVEN, LOW);
      mux_odd_power_enabled = true;
      mux_even_power_enabled = false;
      break;

    default:
      disable_mux_power_rails();
      break;
  }
  delay(100);
}

}

void hardware::i2c::enable() {
  if (!mux_present) {
    enable_legacy_power_rail();
  }
}

void hardware::i2c::disable() {
  if (!mux_present) {
    disable_legacy_power_rail();
    return;
  }
  disable_mux_power_rails();
}

bool hardware::i2c::isEnabled() {
  if (!mux_present) {
    return legacy_power_enabled;
  }
  return mux_odd_power_enabled || mux_even_power_enabled;
}

bool hardware::i2c::initialize() {
  Wire.begin(config::i2c::BUS_0.sda_gpio, config::i2c::BUS_0.scl_gpio,
             config::i2c::FREQUENCY_KHZ * 1000);
  Wire.setTimeOut(100);

  Wire1.begin(config::i2c::BUS_1.sda_gpio, config::i2c::BUS_1.scl_gpio,
              config::i2c::FREQUENCY_KHZ * 1000);
  Wire1.setTimeOut(100);

  mux_present = mux.begin();
  return true;
}

bool hardware::i2c::accessBus(BusDescriptor *descriptor) {
  if (!descriptor) return false;

  switch (descriptor->bus) {
    case Bus::Bus0:
      descriptor->wire = &Wire;
      descriptor->ready = true;
      return true;
    case Bus::Bus1:
      descriptor->wire = &Wire1;
      descriptor->ready = true;
      return true;
    default:
      descriptor->wire = nullptr;
      descriptor->ready = false;
      return false;
  }
}

bool hardware::i2c::accessTopology(TopologySnapshot *snapshot) {
  if (!snapshot) return false;
  snapshot->legacy_power_enabled = legacy_power_enabled;
  snapshot->mux_present = mux_present;
  snapshot->mux_address = config::i2c::MUX_ADDR;
  snapshot->mux_odd_power_enabled = mux_odd_power_enabled;
  snapshot->mux_even_power_enabled = mux_even_power_enabled;
  return true;
}

bool hardware::i2c::accessDevice(DeviceAccessCommand *command) {
  if (!command) return false;

  BusDescriptor descriptor = {
    .bus = command->bus,
    .wire = nullptr,
    .ready = false,
  };
  if (!hardware::i2c::accessBus(&descriptor) || !descriptor.ready) {
    command->wire = nullptr;
    command->ok = false;
    return false;
  }

  if (command->mux_channel >= 0) {
    if (!mux_present || command->bus != Bus::Bus1) {
      command->wire = nullptr;
      command->ok = false;
      return false;
    }
    enable_mux_power_for_channel(command->mux_channel);
    if (!mux.selectChannel((uint8_t)command->mux_channel)) {
      command->wire = nullptr;
      command->ok = false;
      return false;
    }
  } else if (!mux_present) {
    enable_legacy_power_rail();
  }

  command->wire = descriptor.wire;
  command->ok = true;
  return true;
}

void hardware::i2c::clearSelection() {
  if (mux_present) {
    mux.disableAllChannels();
    disable_mux_power_rails();
  }
}

static inline int clamp(int pos, size_t limit) {
  return (pos >= (int)limit) ? (int)limit - 1 : pos;
}

bool hardware::i2c::scan(ScanCommand *command) {
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
  if (mux_present) {
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

    hardware::i2c::clearSelection();
  } else {
    pos += snprintf(buf + pos, buf_size - pos, "mux: (not present)\r\n");
    pos = clamp(pos, buf_size);
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
  hardware::i2c::initialize();
  hardware::i2c::TopologySnapshot snapshot = {};
  hardware::i2c::accessTopology(&snapshot);
  if (!snapshot.mux_present) {
    TEST_IGNORE_MESSAGE("mux not present on this board");
    return;
  }
  TEST_MESSAGE("TCA9548A initialized on Wire1");
}

static void i2c_mux_test_is_connected(void) {
  TEST_MESSAGE("user checks if the mux is on the I2C bus");
  hardware::i2c::TopologySnapshot snapshot = {};
  hardware::i2c::accessTopology(&snapshot);
  if (!snapshot.mux_present) {
    TEST_IGNORE_MESSAGE("mux not present on this board");
    return;
  }
  TEST_ASSERT_TRUE_MESSAGE(snapshot.mux_present,
    "device: mux not found at 0x70");
  TEST_MESSAGE("mux is connected");
}

static void i2c_mux_test_channel_count(void) {
  TEST_MESSAGE("user verifies mux has 8 channels");
  hardware::i2c::TopologySnapshot snapshot = {};
  hardware::i2c::accessTopology(&snapshot);
  if (!snapshot.mux_present) {
    TEST_IGNORE_MESSAGE("mux not present on this board");
    return;
  }
  TEST_ASSERT_EQUAL_UINT8_MESSAGE(8, hardware::i2c::mux.channelCount(),
    "device: TCA9548A should have 8 channels");
  TEST_MESSAGE("8 channels confirmed");
}

static void i2c_mux_test_select_and_verify(void) {
  TEST_MESSAGE("user selects channel 0 and verifies mask");
  hardware::i2c::TopologySnapshot snapshot = {};
  hardware::i2c::accessTopology(&snapshot);
  if (!snapshot.mux_present) {
    TEST_IGNORE_MESSAGE("mux not present on this board");
    return;
  }

  TEST_ASSERT_FALSE_MESSAGE(snapshot.mux_even_power_enabled,
    "device: even mux rail should start disabled");
  TEST_ASSERT_FALSE_MESSAGE(snapshot.mux_odd_power_enabled,
    "device: odd mux rail should start disabled");

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

static void i2c_mux_test_channel_power_mapping(void) {
  TEST_MESSAGE("user verifies documented mux channel power rail mapping");
  hardware::i2c::TopologySnapshot snapshot = {};
  hardware::i2c::accessTopology(&snapshot);
  if (!snapshot.mux_present) {
    TEST_IGNORE_MESSAGE("mux not present on this board");
    return;
  }

  hardware::i2c::DeviceAccessCommand even_command = {
    .bus = hardware::i2c::Bus::Bus1,
    .mux_channel = 0,
    .wire = nullptr,
    .ok = false,
  };
  TEST_ASSERT_TRUE_MESSAGE(hardware::i2c::accessDevice(&even_command),
    "device: accessDevice failed for mux channel 0");
  hardware::i2c::accessTopology(&snapshot);
  TEST_ASSERT_TRUE_MESSAGE(snapshot.mux_even_power_enabled,
    "device: even mux channels should enable GPIO 6 rail");
  TEST_ASSERT_FALSE_MESSAGE(snapshot.mux_odd_power_enabled,
    "device: odd mux rail should remain off for even channels");
  hardware::i2c::clearSelection();

  hardware::i2c::DeviceAccessCommand odd_command = {
    .bus = hardware::i2c::Bus::Bus1,
    .mux_channel = 1,
    .wire = nullptr,
    .ok = false,
  };
  TEST_ASSERT_TRUE_MESSAGE(hardware::i2c::accessDevice(&odd_command),
    "device: accessDevice failed for mux channel 1");
  hardware::i2c::accessTopology(&snapshot);
  TEST_ASSERT_TRUE_MESSAGE(snapshot.mux_odd_power_enabled,
    "device: odd mux channels should enable GPIO 1 rail");
  TEST_ASSERT_FALSE_MESSAGE(snapshot.mux_even_power_enabled,
    "device: even mux rail should remain off for odd channels");
  hardware::i2c::clearSelection();

  hardware::i2c::accessTopology(&snapshot);
  TEST_ASSERT_FALSE_MESSAGE(snapshot.mux_even_power_enabled,
    "device: even mux rail should be off after clearSelection");
  TEST_ASSERT_FALSE_MESSAGE(snapshot.mux_odd_power_enabled,
    "device: odd mux rail should be off after clearSelection");
}

static void i2c_mux_test_scan(void) {
  TEST_MESSAGE("user scans all I2C buses and mux channels");
  hardware::i2c::initialize();

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
  hardware::i2c::TopologySnapshot snapshot = {};
  hardware::i2c::accessTopology(&snapshot);
  if (!snapshot.mux_present) {
    TEST_IGNORE_MESSAGE("mux not present on this board");
    return;
  }

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
  hardware::i2c::TopologySnapshot snapshot = {};
  hardware::i2c::accessTopology(&snapshot);
  if (!snapshot.mux_present) {
    TEST_IGNORE_MESSAGE("mux not present on this board");
    return;
  }
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

void hardware::i2c::test() {
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
  it("user observes that mux channel power rails follow the documented mapping",
     i2c_mux_test_channel_power_mapping);
  it("user observes that disableAllChannels clears the mask",
     i2c_mux_test_disable_all_clears_mask);
  it("user observes that enable then disable roundtrips correctly",
     i2c_mux_test_enable_disable_roundtrip);
}

#endif
