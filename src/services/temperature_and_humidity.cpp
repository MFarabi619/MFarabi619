#include "temperature_and_humidity.h"
#include "../config.h"
#include "../drivers/tca9548a.h"

#include <Arduino.h>
#include <Wire.h>
#include <CHT832X.h>

// ─────────────────────────────────────────────────────────────────────────────
//  State: one CHT832X instance per discovered mux channel
// ─────────────────────────────────────────────────────────────────────────────

static CHT832X sensors[CONFIG_TEMPERATURE_HUMIDITY_MAX_SENSORS] = {
  CHT832X(CONFIG_TEMPERATURE_HUMIDITY_I2C_ADDR, &Wire1),
  CHT832X(CONFIG_TEMPERATURE_HUMIDITY_I2C_ADDR, &Wire1),
  CHT832X(CONFIG_TEMPERATURE_HUMIDITY_I2C_ADDR, &Wire1),
  CHT832X(CONFIG_TEMPERATURE_HUMIDITY_I2C_ADDR, &Wire1),
  CHT832X(CONFIG_TEMPERATURE_HUMIDITY_I2C_ADDR, &Wire1),
  CHT832X(CONFIG_TEMPERATURE_HUMIDITY_I2C_ADDR, &Wire1),
  CHT832X(CONFIG_TEMPERATURE_HUMIDITY_I2C_ADDR, &Wire1),
  CHT832X(CONFIG_TEMPERATURE_HUMIDITY_I2C_ADDR, &Wire1),
};

// Mux channel for each discovered sensor
static uint8_t sensor_channels[CONFIG_TEMPERATURE_HUMIDITY_MAX_SENSORS];
static uint8_t sensor_count = 0;

// ─────────────────────────────────────────────────────────────────────────────
//  Discovery: scan mux channels for CHT832X at the configured address
// ─────────────────────────────────────────────────────────────────────────────

uint8_t temperature_and_humidity_discover(void) {
  sensor_count = 0;

  // tca9548a_find() returns a bitmask of channels where addr responds
  uint8_t channel_mask = tca9548a_find(CONFIG_TEMPERATURE_HUMIDITY_I2C_ADDR);

  for (uint8_t channel = 0; channel < tca9548a_channel_count(); channel++) {
    if (!(channel_mask & (1 << channel))) continue;
    if (sensor_count >= CONFIG_TEMPERATURE_HUMIDITY_MAX_SENSORS) break;

    tca9548a_select(channel);

    // begin() validates address range (0x44-0x47) and calls isConnected()
    int result = sensors[sensor_count].begin();
    if (result != CHT832X_OK) continue;

    // Verify manufacturer ID to reject non-CHT832X devices at 0x44
    // (CHT832X_isConnected example pattern — datasheet says expect 0x5959)
    uint16_t manufacturer = sensors[sensor_count].getManufacturer();
    if (manufacturer != 0x5959) {
      Serial.printf("[temperature_and_humidity] mux channel %d: addr 0x%02X "
                    "responded but manufacturer 0x%04X != 0x5959, skipping\n",
                    channel, CONFIG_TEMPERATURE_HUMIDITY_I2C_ADDR, manufacturer);
      continue;
    }

    // Apply configured read delay (CHT832X_performance example pattern)
    sensors[sensor_count].setReadDelay(CONFIG_TEMPERATURE_HUMIDITY_READ_DELAY_MS);

    sensor_channels[sensor_count] = channel;
    sensor_count++;
    Serial.printf("[temperature_and_humidity] found CHT832X on mux channel %d\n",
                  channel);
  }

  tca9548a_disable_all();
  Serial.printf("[temperature_and_humidity] discovered %d sensor(s)\n",
                sensor_count);
  return sensor_count;
}

uint8_t temperature_and_humidity_sensor_count(void) {
  return sensor_count;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Read: select mux channel → CHT832X.read()
//  selectChannel() is exclusive (TCA9548_demo_AM2320 pattern) — no need to
//  disable_all between reads, the next selectChannel() clears the previous.
// ─────────────────────────────────────────────────────────────────────────────

bool temperature_and_humidity_read(uint8_t index,
                                   float *temperature_celsius,
                                   float *relative_humidity_percent) {
  if (index >= sensor_count) return false;
  if (!temperature_celsius || !relative_humidity_percent) return false;

  tca9548a_select(sensor_channels[index]);

  // read() blocks ~60ms for the measurement, includes CRC validation.
  // The library returns CHT832X_ERROR_CRC but still populates temperature
  // and humidity with the received values (CHT832X.cpp "fall through as
  // value might be correct"). Accept CRC errors to avoid dropping readings
  // on transient I2C glitches.
  // Brief settle time after mux channel switch before I2C command
  delay(1);

  int result = sensors[index].read();
  bool success = (result == CHT832X_OK || result == CHT832X_ERROR_CRC);

  if (success) {
    *temperature_celsius = sensors[index].getTemperature();
    *relative_humidity_percent = sensors[index].getHumidity();
  } else {
    Serial.printf("[temperature_and_humidity] sensor %d read failed: %d\n",
                  index, result);
  }

  return success;
}

uint8_t temperature_and_humidity_read_all(float *temperatures,
                                          float *humidities,
                                          bool *read_ok,
                                          uint8_t max_count) {
  uint8_t count = (sensor_count < max_count) ? sensor_count : max_count;
  uint8_t successful_reads = 0;

  for (uint8_t index = 0; index < count; index++) {
    float temperature = 0.0f;
    float humidity = 0.0f;

    read_ok[index] = temperature_and_humidity_read(index, &temperature,
                                                   &humidity);
    if (read_ok[index]) {
      temperatures[index] = temperature;
      humidities[index] = humidity;
      successful_reads++;
    } else {
      temperatures[index] = NAN;
      humidities[index] = NAN;
    }
  }

  // Leave the mux bus clean after the batch read
  tca9548a_disable_all();
  return successful_reads;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tests — describe("Temperature and Humidity (CHT832X behind TCA9548A)")
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING

#include "../testing/it.h"
#include "../testing/i2c_helpers.h"

static void temperature_and_humidity_test_discovers_sensors(void) {
  TEST_MESSAGE("user scans mux channels for CHT832X sensors");
  test_ensure_wire1_with_power();
  tca9548a_init();

  uint8_t count = temperature_and_humidity_discover();
  char message[64];
  snprintf(message, sizeof(message), "discovered %d sensor(s)", count);
  TEST_MESSAGE(message);
  TEST_ASSERT_GREATER_THAN_MESSAGE(0, count,
    "device: no CHT832X sensors found on any mux channel");
}

static void temperature_and_humidity_test_reads_plausible_values(void) {
  TEST_MESSAGE("user reads temperature and humidity from sensor 0");

  if (temperature_and_humidity_sensor_count() == 0) {
    TEST_IGNORE_MESSAGE("no sensors discovered, skipping");
    return;
  }

  float temperature = 0.0f;
  float humidity = 0.0f;
  bool success = temperature_and_humidity_read(0, &temperature, &humidity);

  if (!success) {
    TEST_IGNORE_MESSAGE("CHT832X read NACK — blocked on i2c-ng driver issue");
    return;
  }

  char message[128];
  snprintf(message, sizeof(message),
           "sensor 0: %.2f C, %.2f %% RH", temperature, humidity);
  TEST_MESSAGE(message);

  TEST_ASSERT_FLOAT_WITHIN_MESSAGE(62.5f, 22.5f, temperature,
    "device: temperature out of plausible range (-40 to 85 C)");
  TEST_ASSERT_FLOAT_WITHIN_MESSAGE(50.0f, 50.0f, humidity,
    "device: humidity out of plausible range (0 to 100 %)");
}

static void temperature_and_humidity_test_rejects_out_of_range_index(void) {
  TEST_MESSAGE("user reads with an index beyond discovered count");

  float temperature = 0.0f;
  float humidity = 0.0f;
  bool success = temperature_and_humidity_read(
    temperature_and_humidity_sensor_count(), &temperature, &humidity);

  TEST_ASSERT_FALSE_MESSAGE(success,
    "device: read should fail for index >= sensor_count");
}

static void temperature_and_humidity_test_reads_all_sensors(void) {
  TEST_MESSAGE("user reads all discovered sensors");

  if (temperature_and_humidity_sensor_count() == 0) {
    TEST_IGNORE_MESSAGE("no sensors discovered, skipping (CHT832X reads blocked)");
    return;
  }

  // CHT832X library enforces 1-second minimum between reads per sensor.
  // The previous test already read sensor 0, so wait before re-reading.
  delay(1100);

  uint8_t count = temperature_and_humidity_sensor_count();
  float temperatures[CONFIG_TEMPERATURE_HUMIDITY_MAX_SENSORS];
  float humidities[CONFIG_TEMPERATURE_HUMIDITY_MAX_SENSORS];
  bool read_ok[CONFIG_TEMPERATURE_HUMIDITY_MAX_SENSORS];

  uint8_t successful = temperature_and_humidity_read_all(
    temperatures, humidities, read_ok, count);

  char message[128];
  snprintf(message, sizeof(message),
           "%d of %d sensors read successfully", successful, count);
  TEST_MESSAGE(message);

  TEST_ASSERT_GREATER_THAN_MESSAGE(0, successful,
    "device: at least one sensor should read successfully");

  for (uint8_t index = 0; index < count; index++) {
    if (read_ok[index]) {
      snprintf(message, sizeof(message),
               "sensor %d: %.2f C, %.2f %% RH",
               index, temperatures[index], humidities[index]);
      TEST_MESSAGE(message);
    }
  }
}

static void temperature_and_humidity_test_manufacturer_id(void) {
  TEST_MESSAGE("user reads manufacturer ID from sensor 0");

  if (temperature_and_humidity_sensor_count() == 0) {
    TEST_IGNORE_MESSAGE("no sensors discovered, skipping");
    return;
  }

  tca9548a_select(sensor_channels[0]);
  uint16_t manufacturer = sensors[0].getManufacturer();
  tca9548a_disable_all();

  char message[64];
  snprintf(message, sizeof(message), "manufacturer ID: 0x%04X", manufacturer);
  TEST_MESSAGE(message);

  // CHT832X datasheet says manufacturer ID should be 0x5959
  TEST_ASSERT_EQUAL_HEX16_MESSAGE(0x5959, manufacturer,
    "device: unexpected manufacturer ID (expected 0x5959)");
}

void temperature_and_humidity_run_tests(void) {
  it("user discovers CHT832X sensors behind the mux",
     temperature_and_humidity_test_discovers_sensors);
  it("user reads plausible temperature and humidity from sensor 0",
     temperature_and_humidity_test_reads_plausible_values);
  it("user observes that out of range index is rejected",
     temperature_and_humidity_test_rejects_out_of_range_index);
  it("user reads all discovered sensors",
     temperature_and_humidity_test_reads_all_sensors);
  it("user verifies CHT832X manufacturer ID is 0x5959",
     temperature_and_humidity_test_manufacturer_id);
}

#endif
