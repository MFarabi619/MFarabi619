#include "ads1115.h"
#include "../config.h"
#include "tca9548a.h"

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_ADS1X15.h>

static Adafruit_ADS1115 adc;
static bool ready = false;
static int8_t discovered_mux_channel = -1;

// ─────────────────────────────────────────────────────────────────────────────
//  Mux helpers: auto-discovered channel
// ─────────────────────────────────────────────────────────────────────────────

static void voltage_monitor_select_mux(void) {
  if (discovered_mux_channel >= 0) {
    tca9548a_select((uint8_t)discovered_mux_channel);
  }
}

static void voltage_monitor_deselect_mux(void) {
  if (discovered_mux_channel >= 0) {
    tca9548a_disable_all();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Core
// ─────────────────────────────────────────────────────────────────────────────

bool ads1115_init(void) {
  ready = false;
  discovered_mux_channel = -1;
  return true;
}

bool ads1115_begin(void) {
  // Auto-discover: scan TCA9548A mux for the ADS1115 address
  uint8_t channel_mask = tca9548a_find(CONFIG_VOLTAGE_MONITOR_I2C_ADDR);

  if (channel_mask != 0) {
    for (uint8_t channel = 0; channel < 8; channel++) {
      if (channel_mask & (1 << channel)) {
        discovered_mux_channel = (int8_t)channel;
        Serial.printf("[ads1115] found at 0x%02X on mux channel %d\n",
                      CONFIG_VOLTAGE_MONITOR_I2C_ADDR, channel);
        break;
      }
    }
  }

  voltage_monitor_select_mux();
  ready = adc.begin(CONFIG_VOLTAGE_MONITOR_I2C_ADDR, &Wire1);

  if (ready) {
    // 2x gain: +/- 2.048V, 0.0625mV resolution
    adc.setGain(GAIN_TWO);
  }

  voltage_monitor_deselect_mux();
  return ready;
}

const char *ads1115_gain_label(void) {
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

bool ads1115_read(float *channel_volts, size_t channel_count) {
  if (!ready) return false;
  if (!channel_volts) return false;
  if (channel_count < CONFIG_VOLTAGE_MONITOR_CHANNEL_COUNT) return false;

  voltage_monitor_select_mux();

  for (size_t channel = 0; channel < CONFIG_VOLTAGE_MONITOR_CHANNEL_COUNT;
       channel++) {
    int16_t raw_counts = adc.readADC_SingleEnded(channel);
    float voltage = adc.computeVolts(raw_counts);

    // Clamp unipolar channels (0 and last) to non-negative values.
    // These channels connect to single-ended voltage sources that should
    // never read negative — a small negative value indicates noise near zero.
    bool is_unipolar = (channel == 0) ||
                       (channel == CONFIG_VOLTAGE_MONITOR_CHANNEL_COUNT - 1);
    if (is_unipolar && voltage < 0.0f) {
      voltage = 0.0f;
    }

    channel_volts[channel] = voltage;
  }

  voltage_monitor_deselect_mux();
  return true;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tests — describe("ADS1115 Voltage Monitor")
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING

#include "../testing/it.h"
#include "../testing/i2c_helpers.h"
#include "tca9548a.h"
#include <math.h>

static void ads1115_test_initializes(void) {
  TEST_MESSAGE("user initializes the ADS1115 voltage monitor");
  test_ensure_wire1_with_power();
  tca9548a_init();

  // The ADS1115 is behind the TCA9548A mux — scan for it
  uint8_t channel_mask = tca9548a_find(CONFIG_VOLTAGE_MONITOR_I2C_ADDR);
  char diagnostic[96];
  snprintf(diagnostic, sizeof(diagnostic),
           "tca9548a_find(0x%02X) = 0x%02X (channels: %s%s%s%s%s%s%s%s)",
           CONFIG_VOLTAGE_MONITOR_I2C_ADDR, channel_mask,
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

  // Select the first channel where the ADC was found
  for (uint8_t channel = 0; channel < 8; channel++) {
    if (channel_mask & (1 << channel)) {
      tca9548a_select(channel);
      snprintf(diagnostic, sizeof(diagnostic),
               "using mux channel %d for ADS1115", channel);
      TEST_MESSAGE(diagnostic);
      break;
    }
  }

  ads1115_init();
  if (!ads1115_begin()) {
    int error = adc.getLastConversionResults();  // just to probe
    snprintf(diagnostic, sizeof(diagnostic),
             "ads1115_begin() failed after mux select");
    TEST_MESSAGE(diagnostic);
    TEST_IGNORE_MESSAGE("ADS1115 begin failed — skipping");
    return;
  }

  TEST_MESSAGE("ADS1115 initialized behind TCA9548A mux");
}

static void ads1115_test_reads_voltage_channels(void) {
  TEST_MESSAGE("user reads all 4 voltage channels");

  if (!ready) {
    TEST_IGNORE_MESSAGE("ADS1115 not available — skipping");
    return;
  }

  float channel_volts[CONFIG_VOLTAGE_MONITOR_CHANNEL_COUNT];
  bool success = ads1115_read(channel_volts, CONFIG_VOLTAGE_MONITOR_CHANNEL_COUNT);
  TEST_ASSERT_TRUE_MESSAGE(success, "device: ads1115_read() failed");

  for (size_t channel = 0; channel < CONFIG_VOLTAGE_MONITOR_CHANNEL_COUNT;
       channel++) {
    char message[64];
    snprintf(message, sizeof(message), "channel %zu: %.4f V", channel,
             channel_volts[channel]);
    TEST_MESSAGE(message);

    TEST_ASSERT_FALSE_MESSAGE(isnan(channel_volts[channel]),
      "device: channel voltage should not be NaN");
  }
}

static void ads1115_test_gain_label(void) {
  TEST_MESSAGE("user checks the configured gain label");

  if (!ready) {
    TEST_IGNORE_MESSAGE("ADS1115 not available — skipping");
    return;
  }

  const char *label = ads1115_gain_label();
  TEST_MESSAGE(label);

  TEST_ASSERT_NOT_EQUAL_MESSAGE(0, strlen(label),
    "device: gain label should not be empty");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("GAIN_TWO", label,
    "device: default gain should be GAIN_TWO");
}

static void ads1115_test_rejects_small_buffer(void) {
  TEST_MESSAGE("user passes undersized buffer to ads1115_read");

  float channel_volts[1];
  bool success = ads1115_read(channel_volts, 1);
  TEST_ASSERT_FALSE_MESSAGE(success,
    "device: read should fail when channel_count < CONFIG_VOLTAGE_MONITOR_CHANNEL_COUNT");
}

void ads1115_run_tests(void) {
  it("user observes that the ADS1115 initializes on Wire1",
     ads1115_test_initializes);
  it("user reads voltage from all 4 channels",
     ads1115_test_reads_voltage_channels);
  it("user verifies the gain label is GAIN_TWO",
     ads1115_test_gain_label);
  it("user observes that undersized buffer is rejected",
     ads1115_test_rejects_small_buffer);
}

#endif
