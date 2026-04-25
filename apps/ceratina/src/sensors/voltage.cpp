#include "voltage.h"
#include "registry.h"
#include <config.h>
#include <i2c.h>

#include <Adafruit_ADS1X15.h>
#include <Arduino.h>

static bool ready = false;
static uint8_t resolved_bus = 0;
static uint8_t resolved_address = 0;
static int8_t resolved_mux_channel = config::i2c::DIRECT_CHANNEL;

static Adafruit_ADS1115 adc;

namespace {

void apply_selection(void) {
  if (resolved_mux_channel >= 0) {
    hardware::i2c::DeviceAccessCommand command = {
        .bus = resolved_bus == 0 ? hardware::i2c::Bus::Bus0
                                 : hardware::i2c::Bus::Bus1,
        .mux_channel = resolved_mux_channel,
        .wire = nullptr,
        .ok = false,
    };
    hardware::i2c::accessDevice(&command);
  }
}

bool probe_ads1115_discovered(const hardware::i2c::DiscoveredDevice &dev) {
  hardware::i2c::DeviceAccessCommand command = {
      .bus = dev.bus == 0 ? hardware::i2c::Bus::Bus0 : hardware::i2c::Bus::Bus1,
      .mux_channel = dev.mux_channel,
      .wire = nullptr,
      .ok = false,
  };
  if (!hardware::i2c::accessDevice(&command))
    return false;

  bool ok = adc.begin(dev.address, command.wire);
  hardware::i2c::clearSelection();
  if (!ok)
    return false;

  resolved_bus = dev.bus;
  resolved_address = dev.address;
  resolved_mux_channel = dev.mux_channel;
  ready = true;
  adc.setGain(GAIN_ONE);

  sensors::registry::add({
      .kind = SensorKind::Voltage,
      .name = "Voltage",
      .isAvailable = sensors::voltage::isAvailable,
      .instanceCount = []() -> uint8_t { return 1; },
      .poll = [](uint8_t, void *out, size_t cap) -> bool {
        if (cap < sizeof(VoltageSensorData))
          return false;
        return sensors::voltage::access(static_cast<VoltageSensorData *>(out));
      },
      .data_size = sizeof(VoltageSensorData),
  });
  return true;
}

} // namespace

void sensors::voltage::registerProbes() {
  ready = false;
  resolved_mux_channel = config::i2c::DIRECT_CHANNEL;
  hardware::i2c::registerProbe({0x48, probe_ads1115_discovered, "ADS1115", 10});
}

bool sensors::voltage::isAvailable() { return ready; }

const char *sensors::voltage::accessGainLabel() {
  if (!ready)
    return "NOT_READY";

  switch (adc.getGain()) {
  case GAIN_TWOTHIRDS:
    return "GAIN_TWOTHIRDS";
  case GAIN_ONE:
    return "GAIN_ONE";
  case GAIN_TWO:
    return "GAIN_TWO";
  case GAIN_FOUR:
    return "GAIN_FOUR";
  case GAIN_EIGHT:
    return "GAIN_EIGHT";
  case GAIN_SIXTEEN:
    return "GAIN_SIXTEEN";
  default:
    return "GAIN_UNKNOWN";
  }
}

bool sensors::voltage::access(VoltageSensorData *sensor_data) {
  if (!ready)
    return false;
  if (!sensor_data)
    return false;

  apply_selection();

  for (size_t channel = 0; channel < config::voltage::CHANNEL_COUNT;
       channel++) {
    int16_t raw_counts = adc.readADC_SingleEnded(channel);
    float voltage = adc.computeVolts(raw_counts);

    bool is_unipolar =
        (channel == 0) || (channel == config::voltage::CHANNEL_COUNT - 1);
    if (is_unipolar && voltage < 0.0f) {
      voltage = 0.0f;
    }

    sensor_data->channel_volts[channel] = voltage;
  }

  hardware::i2c::clearSelection();
  return true;
}

#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

static void test_voltage_initializes(void) {
  GIVEN("Wire1 with power enabled");
  WHEN("the ADS1115 is initialized");
  test_ensure_wire1_with_power();
  hardware::i2c::initialize();

  sensors::voltage::registerProbes();
  hardware::i2c::runDiscovery();
  hardware::i2c::probeAll();
  if (!sensors::voltage::isAvailable()) {
    TEST_IGNORE_MESSAGE("ADS1115 not found — skipping");
    return;
  }
}

static void test_voltage_reads_channels(void) {
  GIVEN("an initialized ADS1115");
  WHEN("all 4 channels are read");

  if (!sensors::voltage::isAvailable()) {
    TEST_IGNORE_MESSAGE("ADS1115 not available — skipping");
    return;
  }

  VoltageSensorData sensor_data = {};
  bool success = sensors::voltage::access(&sensor_data);
  TEST_ASSERT_TRUE_MESSAGE(success, "device: voltage::access() failed");

  for (size_t channel = 0; channel < config::voltage::CHANNEL_COUNT;
       channel++) {
    char message[64];
    snprintf(message, sizeof(message), "channel %zu: %.4f V", channel,
             sensor_data.channel_volts[channel]);
    TEST_MESSAGE(message);

    TEST_ASSERT_FLOAT_IS_DETERMINATE_MESSAGE(
        sensor_data.channel_volts[channel],
        "device: channel voltage must be a finite number (not NaN or "
        "infinity)");
  }
}

static void test_voltage_gain_label(void) {
  GIVEN("an initialized ADS1115");
  WHEN("the gain label is queried");

  if (!sensors::voltage::isAvailable()) {
    TEST_IGNORE_MESSAGE("ADS1115 not available — skipping");
    return;
  }

  const char *label = sensors::voltage::accessGainLabel();
  TEST_MESSAGE(label);

  TEST_ASSERT_NOT_EMPTY_MESSAGE(label,
                                "device: gain label should not be empty");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("GAIN_ONE", label,
                                   "device: default gain should be GAIN_ONE");
}

static void test_voltage_rejects_null_buffer(void) {
  WHEN("a null buffer is passed to access");

  bool success = sensors::voltage::access(nullptr);
  TEST_ASSERT_FALSE_MESSAGE(
      success, "device: read should fail when sensor_data is null");
}

void sensors::voltage::test() {
  MODULE("Voltage");
  RUN_TEST(test_voltage_initializes);
  RUN_TEST(test_voltage_reads_channels);
  RUN_TEST(test_voltage_gain_label);
  RUN_TEST(test_voltage_rejects_null_buffer);
}

#endif
