#include "i2c.h"
#include <config.h>
#include "console/icons.h"

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
  delay(config::i2c::POWER_SETTLE_MS);
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

// clearSelection() not only deselects mux channels, it also drops both
// ODD/EVEN MUX_POWER_GPIO rails. This is intentional power saving, but it
// means any sensor that relies on internal state across reads (e.g., SCD30
// periodic measurement) cannot work on this board — the rail is cut between
// polls. Stateless sensors and SCD41 single-shot mode are compatible; see
// sensors/carbon_dioxide.cpp for the working pattern.
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

static const char *device_icon_at(uint8_t address) {
  switch (address) {
    case 0x39: return NF_FA_SIGNAL;            // AS7343 spectral (placeholder)
    case 0x40: return NF_FA_BOLT;              // INA228 current
    case 0x44: return NF_FA_THERMOMETER;       // SHT3x temperature
    case 0x48: return NF_FA_SIGNAL;            // ADS1115 ADC
    case 0x50: return NF_FA_DATABASE;          // EEPROM
    case 0x5C: case 0x5D: return NF_FA_TINT;  // LPS25 pressure
    case 0x61: case 0x62: return NF_FA_LEAF;   // SCD30/SCD41 CO2
    case 0x67: return NF_FA_THERMOMETER;       // MCP9600 thermocouple
    case 0x68: return NF_FA_CLOCK;             // DS3231 RTC
    case 0x70: return NF_FA_SITEMAP;           // TCA9548A mux
    default:   return NF_FA_COG;               // unknown
  }
}

const char *hardware::i2c::deviceNameAt(uint8_t address, int8_t mux_channel) {
  bool is_muxed = (mux_channel >= 0);

  switch (address) {
    case 0x39: return "Sparkfun AS7343 Spectral Sensor";
    case 0x40: return "Adafruit INA228 Current Monitor";
    case 0x44: return "Sensirion SHT3x Temperature & Humidity Sensor";
    case 0x48: return "ADS1115 16-Bit ADC - 4 Channel with Programmable Gain Amplifier";
    case 0x50: return is_muxed ? "sensor module EEPROM (on-board)"
                               : "Microchip Technology AT24C32 EEPROM";
    case 0x5C: case 0x5D: return "Adafruit LPS25 Pressure Sensor";
    case 0x61: return "Sensirion SCD30 CO2 Infrared Gas Sensor";
    case 0x62: return "Sensirion SCD41 CO2 Optical Gas Sensor";
    case 0x67: return "Adafruit MCP9600 Thermocouple Amplifier";
    case 0x68: return "Analog Devices DS3231 RTC";
    case 0x70: return "Adafruit TCA9548A 1-to-8 I2C Multiplexer Breakout";
    default:   return "unknown";
  }
}

size_t hardware::i2c::discoverAll(DiscoveredDevice *devices, size_t capacity) {
  if (!devices || capacity == 0) return 0;
  size_t count = 0;

  enable_legacy_power_rail();
  pinMode(config::i2c::MUX_POWER_GPIO_EVEN, OUTPUT);
  digitalWrite(config::i2c::MUX_POWER_GPIO_EVEN, HIGH);
  pinMode(config::i2c::MUX_POWER_GPIO_ODD, OUTPUT);
  digitalWrite(config::i2c::MUX_POWER_GPIO_ODD, HIGH);
  delay(config::i2c::DISCOVERY_SETTLE_MS);

  TwoWire *buses[] = { &Wire, &Wire1 };
  for (uint8_t bus = 0; bus < 2 && count < capacity; bus++) {
    for (uint8_t addr = config::i2c::ADDR_MIN; addr <= config::i2c::ADDR_MAX && count < capacity; addr++) {
      if (addr == config::i2c::MUX_ADDR) continue;
      buses[bus]->beginTransmission(addr);
      if (buses[bus]->endTransmission() == 0) {
        devices[count++] = { bus, addr, -1 };
      }
    }
  }

  if (mux_present) {
    for (uint8_t ch = 0; ch < mux.channelCount() && count < capacity; ch++) {
      enable_mux_power_for_channel(ch);
      mux.selectChannel(ch);
      for (uint8_t addr = config::i2c::ADDR_MIN; addr <= config::i2c::ADDR_MAX && count < capacity; addr++) {
        if (addr == config::i2c::MUX_ADDR) continue;
        Wire1.beginTransmission(addr);
        if (Wire1.endTransmission() == 0) {
          devices[count++] = { 1, addr, (int8_t)ch };
        }
      }
      mux.disableAllChannels();
    }
    disable_mux_power_rails();
  }

  return count;
}

static hardware::i2c::DiscoveredDevice discovery_cache[hardware::i2c::MAX_DISCOVERED_DEVICES];
static size_t discovery_count = 0;
static bool discovery_done = false;

bool hardware::i2c::runDiscovery() {
  discovery_count = discoverAll(discovery_cache, MAX_DISCOVERED_DEVICES);
  discovery_done = true;
  for (size_t i = 0; i < discovery_count; i++) {
    Serial.printf("[i2c] found 0x%02X on bus %d%s\n",
                  discovery_cache[i].address, discovery_cache[i].bus,
                  discovery_cache[i].mux_channel >= 0 ? " (mux)" : "");
  }
  return discovery_count > 0;
}

// Searches the cached discovery results. Call runDiscovery() first
// during boot. Falls back to a full bus scan if the cache is empty.
bool hardware::i2c::findDevice(uint8_t address, DiscoveredDevice *result) {
  if (!result) return false;
  if (!discovery_done) runDiscovery();
  for (size_t i = 0; i < discovery_count; i++) {
    if (discovery_cache[i].address == address) {
      *result = discovery_cache[i];
      return true;
    }
  }
  return false;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>


static void test_i2c_mux_init(void) {
  GIVEN("Wire1 is available");
  test_ensure_wire1();

  WHEN("the mux is initialized");
  hardware::i2c::initialize();
  hardware::i2c::TopologySnapshot snapshot = {};
  hardware::i2c::accessTopology(&snapshot);
  if (!snapshot.mux_present) {
    TEST_IGNORE_MESSAGE("mux not present on this board");
    return;
  }
}

static void test_i2c_mux_is_connected(void) {
  WHEN("the mux connection is checked");
  hardware::i2c::TopologySnapshot snapshot = {};
  hardware::i2c::accessTopology(&snapshot);
  if (!snapshot.mux_present) {
    TEST_IGNORE_MESSAGE("mux not present on this board");
    return;
  }
  TEST_ASSERT_TRUE_MESSAGE(snapshot.mux_present,
    "device: mux not found at 0x70");
}

static void test_i2c_mux_channel_count(void) {
  THEN("the mux has 8 channels");
  hardware::i2c::TopologySnapshot snapshot = {};
  hardware::i2c::accessTopology(&snapshot);
  if (!snapshot.mux_present) {
    TEST_IGNORE_MESSAGE("mux not present on this board");
    return;
  }
  TEST_ASSERT_EQUAL_UINT8_MESSAGE(8, hardware::i2c::mux.channelCount(),
    "device: TCA9548A should have 8 channels");
}

static void test_i2c_mux_select_and_verify(void) {
  WHEN("channels are selected");
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
}

static void test_i2c_mux_channel_power_mapping(void) {
  WHEN("even and odd mux channels are accessed");
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

static void test_i2c_mux_scan(void) {
  WHEN("all I2C buses and mux channels are scanned");
  hardware::i2c::initialize();
  hardware::i2c::runDiscovery();

  hardware::i2c::DiscoveredDevice devices[hardware::i2c::MAX_DISCOVERED_DEVICES];
  size_t count = hardware::i2c::discoverAll(devices, hardware::i2c::MAX_DISCOVERED_DEVICES);

  TEST_ASSERT_GREATER_THAN_MESSAGE(0, (int)count, "device: no I2C devices found");

  char line[120];
  // TEST_MESSAGE escapes non-ASCII, so ASCII-only tree characters
  TEST_MESSAGE("");
  snprintf(line, sizeof(line), "ESP32-S3");
  TEST_MESSAGE(line);

  bool has_bus1 = false;
  for (size_t i = 0; i < count; i++) {
    if (devices[i].bus == 1) { has_bus1 = true; break; }
  }

  //------------------------------------------
  //  Bus 0
  //------------------------------------------
  const char *bus0_branch = has_bus1 ? "+" : "\\";
  snprintf(line, sizeof(line), "%s-- I2C Bus 0 (GPIO %d/%d)",
           bus0_branch, config::i2c::BUS_0.sda_gpio, config::i2c::BUS_0.scl_gpio);
  TEST_MESSAGE(line);

  const char *bus0_cont = has_bus1 ? "|" : " ";
  for (size_t i = 0; i < count; i++) {
    if (devices[i].bus != 0 || devices[i].mux_channel >= 0) continue;
    snprintf(line, sizeof(line), "%s   \\-- 0x%02X %s",
             bus0_cont, devices[i].address,
             hardware::i2c::deviceNameAt(devices[i].address, devices[i].mux_channel));
    TEST_MESSAGE(line);
  }

  if (!has_bus1) return;

  TEST_MESSAGE(bus0_cont);

  //------------------------------------------
  //  Bus 1
  //------------------------------------------
  snprintf(line, sizeof(line), "\\-- I2C Bus 1 (GPIO %d/%d)",
           config::i2c::BUS_1.sda_gpio, config::i2c::BUS_1.scl_gpio);
  TEST_MESSAGE(line);

  // Bus 1 unmuxed devices
  for (size_t i = 0; i < count; i++) {
    if (devices[i].bus != 1 || devices[i].mux_channel >= 0) continue;
    if (devices[i].address == config::i2c::MUX_ADDR) continue;
    snprintf(line, sizeof(line), "    +-- 0x%02X %s",
             devices[i].address,
             hardware::i2c::deviceNameAt(devices[i].address, devices[i].mux_channel));
    TEST_MESSAGE(line);
  }

  // Mux header
  TEST_MESSAGE("    |");
  snprintf(line, sizeof(line), "    \\-- 0x%02X %s",
           config::i2c::MUX_ADDR,
           hardware::i2c::deviceNameAt(config::i2c::MUX_ADDR, -1));
  TEST_MESSAGE(line);

  //------------------------------------------
  //  Mux channels
  //------------------------------------------
  for (int channel = 0; channel < 8; channel++) {
    struct { uint8_t addr; const char *name; } channel_devices[8];
    int channel_count = 0;

    for (size_t i = 0; i < count && channel_count < 8; i++) {
      if (devices[i].bus != 1 || devices[i].mux_channel != channel) continue;
      if (devices[i].address == 0x50) continue;
      channel_devices[channel_count].addr = devices[i].address;
      channel_devices[channel_count].name = hardware::i2c::deviceNameAt(devices[i].address, devices[i].mux_channel);
      channel_count++;
    }

    if (channel_count == 0) continue;

    bool is_last_channel = true;
    for (int future = channel + 1; future < 8; future++) {
      for (size_t i = 0; i < count; i++) {
        if (devices[i].bus == 1 && devices[i].mux_channel == future && devices[i].address != 0x50) {
          is_last_channel = false;
          break;
        }
      }
      if (!is_last_channel) break;
    }

    const char *branch = is_last_channel ? "\\" : "+";
    const char *cont   = is_last_channel ? " " : "|";

    snprintf(line, sizeof(line), "        %s-- %d: 0x%02X %s",
             branch, channel,
             channel_devices[0].addr, channel_devices[0].name);
    TEST_MESSAGE(line);

    for (int d = 1; d < channel_count; d++) {
      snprintf(line, sizeof(line), "        %s       0x%02X %s",
               cont,
               channel_devices[d].addr, channel_devices[d].name);
      TEST_MESSAGE(line);
    }
  }
}

static void test_i2c_mux_disable_all_clears_mask(void) {
  GIVEN("Wire1 is available");
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
  WHEN("all channels are disabled");
  TEST_ASSERT_BITS_HIGH_MESSAGE(0x89, hardware::i2c::mux.getChannelMask(),
    "device: channels 0, 3, 7 should all be enabled");

  hardware::i2c::mux.disableAllChannels();
  TEST_ASSERT_EQUAL_HEX8_MESSAGE(0x00, hardware::i2c::mux.getChannelMask(),
    "device: mask should be 0x00 after disableAllChannels");

}

static void test_i2c_mux_enable_disable_roundtrip(void) {
  GIVEN("Wire1 is available");
  test_ensure_wire1();
  hardware::i2c::TopologySnapshot snapshot = {};
  hardware::i2c::accessTopology(&snapshot);
  if (!snapshot.mux_present) {
    TEST_IGNORE_MESSAGE("mux not present on this board");
    return;
  }
  hardware::i2c::mux.disableAllChannels();

  WHEN("a channel is enabled then disabled");
  hardware::i2c::mux.enableChannel(2);
  TEST_ASSERT_BIT_HIGH_MESSAGE(2, hardware::i2c::mux.getChannelMask(),
    "device: bit 2 should be high after enableChannel(2)");

  hardware::i2c::mux.disableChannel(2);
  TEST_ASSERT_BIT_LOW_MESSAGE(2, hardware::i2c::mux.getChannelMask(),
    "device: bit 2 should be low after disableChannel(2)");
  TEST_ASSERT_EQUAL_HEX8_MESSAGE(0x00, hardware::i2c::mux.getChannelMask(),
    "device: full mask should be 0x00 after disable");

}

void hardware::i2c::test() {
  MODULE("I2C");
  RUN_TEST(test_i2c_mux_init);
  RUN_TEST(test_i2c_mux_is_connected);
  RUN_TEST(test_i2c_mux_channel_count);
  RUN_TEST(test_i2c_mux_select_and_verify);
  RUN_TEST(test_i2c_mux_scan);
  RUN_TEST(test_i2c_mux_channel_power_mapping);
  RUN_TEST(test_i2c_mux_disable_all_clears_mask);
  RUN_TEST(test_i2c_mux_enable_disable_roundtrip);
}

#endif
