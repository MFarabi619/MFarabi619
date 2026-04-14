#include "voltage.h"
#include "registry.h"
#include <config.h>
#include <i2c.h>

#include <Adafruit_ADS1X15.h>
#include <Arduino.h>

static bool ready = false;
static config::I2CSensorConfig resolved_config = {
  config::I2CSensorKind::VoltageADS1115,
  0,
  0,
  config::i2c::DIRECT_CHANNEL,
};
static int8_t resolved_mux_channel = config::i2c::DIRECT_CHANNEL;

static Adafruit_ADS1115 adc;

namespace {

bool access_voltage_descriptor(config::I2CSensorConfig *sensor_config) {
  if (!sensor_config) return false;
  for (size_t index = 0; index < config::i2c_topology::DEVICE_COUNT; index++) {
    const config::I2CSensorConfig &candidate = config::i2c_topology::DEVICES[index];
    if (candidate.kind == config::I2CSensorKind::VoltageADS1115) {
      *sensor_config = candidate;
      return true;
    }
  }
  return false;
}

bool probe_device(const config::I2CSensorConfig &sensor_config, int8_t mux_channel) {
  hardware::i2c::DeviceAccessCommand command = {
    .bus = sensor_config.bus == 0 ? hardware::i2c::Bus::Bus0 : hardware::i2c::Bus::Bus1,
    .mux_channel = mux_channel,
    .wire = nullptr,
    .ok = false,
  };
  if (!hardware::i2c::accessDevice(&command)) return false;

  bool ok = adc.begin(sensor_config.address, command.wire);
  hardware::i2c::clearSelection();
  return ok;
}

void apply_selection(void) {
  if (resolved_mux_channel >= 0) {
    hardware::i2c::DeviceAccessCommand command = {
      .bus = resolved_config.bus == 0 ? hardware::i2c::Bus::Bus0 : hardware::i2c::Bus::Bus1,
      .mux_channel = resolved_mux_channel,
      .wire = nullptr,
      .ok = false,
    };
    hardware::i2c::accessDevice(&command);
  }
}

}

bool sensors::voltage::initialize() {
  ready = false;
  resolved_config = {
    config::I2CSensorKind::VoltageADS1115,
    0,
    0,
    config::i2c::DIRECT_CHANNEL,
  };
  resolved_mux_channel = config::i2c::DIRECT_CHANNEL;

  config::I2CSensorConfig sensor_config = {};
  if (!access_voltage_descriptor(&sensor_config)) {
    return false;
  }

  hardware::i2c::TopologySnapshot topology = {};
  hardware::i2c::accessTopology(&topology);

  if (sensor_config.mux_channel == config::i2c::DIRECT_CHANNEL) {
    ready = probe_device(sensor_config, config::i2c::DIRECT_CHANNEL);
  } else if (sensor_config.mux_channel == config::i2c::ANY_MUX_CHANNEL) {
    if (topology.mux_present && sensor_config.bus == 1) {
      uint8_t channel_mask = hardware::i2c::mux.find(sensor_config.address);
      if (channel_mask != 0) {
        for (uint8_t channel = 0; channel < hardware::i2c::mux.channelCount(); channel++) {
          if (channel_mask & (1 << channel)) {
            resolved_mux_channel = (int8_t)channel;
            ready = probe_device(sensor_config, resolved_mux_channel);
            if (ready) {
              Serial.printf("[voltage] found at 0x%02X on mux channel %d\n",
                            sensor_config.address, channel);
              break;
            }
          }
        }
      }
    }
  } else {
    if (topology.mux_present && sensor_config.bus == 1) {
      resolved_mux_channel = sensor_config.mux_channel;
      ready = probe_device(sensor_config, resolved_mux_channel);
    }
  }

  if (ready) {
    resolved_config.kind = sensor_config.kind;
    resolved_config.bus = sensor_config.bus;
    resolved_config.address = sensor_config.address;
    resolved_config.mux_channel = sensor_config.mux_channel;
    adc.setGain(GAIN_TWO);

    sensors::registry::add({
        .kind = SensorKind::Voltage,
        .name = "Voltage",
        .isAvailable = sensors::voltage::isAvailable,
        .instanceCount = []() -> uint8_t { return 1; },
        .poll = [](uint8_t, void *out, size_t cap) -> bool {
            if (cap < sizeof(VoltageSensorData)) return false;
            return sensors::voltage::access(static_cast<VoltageSensorData *>(out));
        },
        .data_size = sizeof(VoltageSensorData),
    });
  }

  hardware::i2c::clearSelection();
  return ready;
}

bool sensors::voltage::isAvailable() {
  return ready;
}

const char *sensors::voltage::accessGainLabel() {
  if (!ready) return "NOT_READY";

  switch (adc.getGain()) {
    case GAIN_TWOTHIRDS: return "GAIN_TWOTHIRDS";
    case GAIN_ONE:       return "GAIN_ONE";
    case GAIN_TWO:       return "GAIN_TWO";
    case GAIN_FOUR:      return "GAIN_FOUR";
    case GAIN_EIGHT:     return "GAIN_EIGHT";
    case GAIN_SIXTEEN:   return "GAIN_SIXTEEN";
    default:             return "GAIN_UNKNOWN";
  }
}

bool sensors::voltage::access(VoltageSensorData *sensor_data) {
  if (!ready) return false;
  if (!sensor_data) return false;

  apply_selection();

  for (size_t channel = 0; channel < config::voltage::CHANNEL_COUNT;
       channel++) {
    int16_t raw_counts = adc.readADC_SingleEnded(channel);
    float voltage = adc.computeVolts(raw_counts);

    bool is_unipolar = (channel == 0) ||
                       (channel == config::voltage::CHANNEL_COUNT - 1);
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

#include <math.h>

static void voltage_test_initializes(void) {
  TEST_MESSAGE("user initializes the ADS1115 voltage monitor");
  test_ensure_wire1_with_power();
  hardware::i2c::initialize();

  if (!sensors::voltage::initialize()) {
    TEST_IGNORE_MESSAGE("voltage::initialize() failed — skipping");
    return;
  }

  TEST_MESSAGE("ADS1115 initialized behind TCA9548A mux");
}

static void voltage_test_reads_channels(void) {
  TEST_MESSAGE("user reads all 4 voltage channels");

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

    TEST_ASSERT_FALSE_MESSAGE(isnan(sensor_data.channel_volts[channel]),
      "device: channel voltage should not be NaN");
  }
}

static void voltage_test_gain_label(void) {
  TEST_MESSAGE("user checks the configured gain label");

  if (!sensors::voltage::isAvailable()) {
    TEST_IGNORE_MESSAGE("ADS1115 not available — skipping");
    return;
  }

  const char *label = sensors::voltage::accessGainLabel();
  TEST_MESSAGE(label);

  TEST_ASSERT_NOT_EQUAL_MESSAGE(0, strlen(label),
    "device: gain label should not be empty");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("GAIN_TWO", label,
    "device: default gain should be GAIN_TWO");
}

static void voltage_test_rejects_null_buffer(void) {
  TEST_MESSAGE("user passes null buffer to read");

  bool success = sensors::voltage::access(nullptr);
  TEST_ASSERT_FALSE_MESSAGE(success,
    "device: read should fail when sensor_data is null");
}

void sensors::voltage::test() {
  it("user observes that the ADS1115 initializes on Wire1",
     voltage_test_initializes);
  it("user reads voltage from all 4 channels",
     voltage_test_reads_channels);
  it("user verifies the gain label is GAIN_TWO",
     voltage_test_gain_label);
  it("user observes that null buffer is rejected",
     voltage_test_rejects_null_buffer);
}

#endif
