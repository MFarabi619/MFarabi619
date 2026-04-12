#include "voltage.h"
#include "../config.h"
#include "../hardware/i2c.h"

#include <Arduino.h>
#include <Wire.h>

static bool ready = false;
static int8_t discovered_mux_channel = -1;

Adafruit_ADS1115 sensors::voltage::ADC;

static void select_mux(void) {
  if (discovered_mux_channel >= 0)
    hardware::i2c::mux.selectChannel((uint8_t)discovered_mux_channel);
}

static void deselect_mux(void) {
  if (discovered_mux_channel >= 0)
    hardware::i2c::mux.disableAllChannels();
}

bool sensors::voltage::initialize() noexcept {
  ready = false;
  discovered_mux_channel = -1;

  uint8_t channel_mask = hardware::i2c::mux.find(config::voltage::I2C_ADDR);

  if (channel_mask != 0) {
    for (uint8_t channel = 0; channel < 8; channel++) {
      if (channel_mask & (1 << channel)) {
        discovered_mux_channel = (int8_t)channel;
        Serial.printf("[voltage] found at 0x%02X on mux channel %d\n",
                      config::voltage::I2C_ADDR, channel);
        break;
      }
    }
  }

  select_mux();
  ready = ADC.begin(config::voltage::I2C_ADDR, &Wire1);

  if (ready) {
    ADC.setGain(GAIN_TWO);
  }

  deselect_mux();
  return ready;
}

bool sensors::voltage::isReady() noexcept {
  return ready;
}

const char *sensors::voltage::accessGainLabel() noexcept {
  if (!ready) return "NOT_READY";

  switch (ADC.getGain()) {
    case GAIN_TWOTHIRDS: return "GAIN_TWOTHIRDS";
    case GAIN_ONE:       return "GAIN_ONE";
    case GAIN_TWO:       return "GAIN_TWO";
    case GAIN_FOUR:      return "GAIN_FOUR";
    case GAIN_EIGHT:     return "GAIN_EIGHT";
    case GAIN_SIXTEEN:   return "GAIN_SIXTEEN";
    default:             return "GAIN_UNKNOWN";
  }
}

bool sensors::voltage::access(VoltageSensorData *sensor_data) noexcept {
  if (!ready) return false;
  if (!sensor_data) return false;

  select_mux();

  for (size_t channel = 0; channel < config::voltage::CHANNEL_COUNT;
       channel++) {
    int16_t raw_counts = ADC.readADC_SingleEnded(channel);
    float voltage = ADC.computeVolts(raw_counts);

    bool is_unipolar = (channel == 0) ||
                       (channel == config::voltage::CHANNEL_COUNT - 1);
    if (is_unipolar && voltage < 0.0f) {
      voltage = 0.0f;
    }

    sensor_data->channel_volts[channel] = voltage;
  }

  deselect_mux();
  return true;
}

#ifdef PIO_UNIT_TESTING

#include "../testing/it.h"
#include "../testing/i2c_helpers.h"
#include <math.h>

static void voltage_test_initializes(void) {
  TEST_MESSAGE("user initializes the ADS1115 voltage monitor");
  test_ensure_wire1_with_power();
  hardware::i2c::initialize();

  uint8_t channel_mask = hardware::i2c::mux.find(config::voltage::I2C_ADDR);
  char diagnostic[96];
  snprintf(diagnostic, sizeof(diagnostic),
           "mux.find(0x%02X) = 0x%02X (channels: %s%s%s%s%s%s%s%s)",
           config::voltage::I2C_ADDR, channel_mask,
           (channel_mask & 0x01) ? "0 " : "",
           (channel_mask & 0x02) ? "1 " : "",
           (channel_mask & 0x04) ? "2 " : "",
           (channel_mask & 0x08) ? "3 " : "",
           (channel_mask & 0x10) ? "4 " : "",
           (channel_mask & 0x20) ? "5 " : "",
           (channel_mask & 0x40) ? "6 " : "",
           (channel_mask & 0x80) ? "7 " : "");
  TEST_MESSAGE(diagnostic);

  if (channel_mask == 0) {
    TEST_IGNORE_MESSAGE("ADS1115 not found at 0x48 on any mux channel — skipping");
    return;
  }

  if (!sensors::voltage::initialize()) {
    TEST_IGNORE_MESSAGE("voltage::initialize() failed — skipping");
    return;
  }

  TEST_MESSAGE("ADS1115 initialized behind TCA9548A mux");
}

static void voltage_test_reads_channels(void) {
  TEST_MESSAGE("user reads all 4 voltage channels");

  if (!sensors::voltage::isReady()) {
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

  if (!sensors::voltage::isReady()) {
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

void sensors::voltage::test() noexcept {
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
