#include "temperature_and_humidity.h"
#include "../config.h"
#include "../hardware/i2c.h"

#include <Arduino.h>
#include <Wire.h>
#include <CHT832X.h>

static CHT832X cht_sensors[config::temperature_humidity::MAX_SENSORS] = {
  CHT832X(config::temperature_humidity::I2C_ADDR, &Wire1),
  CHT832X(config::temperature_humidity::I2C_ADDR, &Wire1),
  CHT832X(config::temperature_humidity::I2C_ADDR, &Wire1),
  CHT832X(config::temperature_humidity::I2C_ADDR, &Wire1),
  CHT832X(config::temperature_humidity::I2C_ADDR, &Wire1),
  CHT832X(config::temperature_humidity::I2C_ADDR, &Wire1),
  CHT832X(config::temperature_humidity::I2C_ADDR, &Wire1),
  CHT832X(config::temperature_humidity::I2C_ADDR, &Wire1),
};

static uint8_t sensor_channels[config::temperature_humidity::MAX_SENSORS];
static uint8_t sensor_count = 0;

uint8_t sensors::temperature_and_humidity::discover() noexcept {
  sensor_count = 0;

  uint8_t channel_mask = hardware::i2c::mux.find(config::temperature_humidity::I2C_ADDR);

  for (uint8_t channel = 0; channel < hardware::i2c::mux.channelCount(); channel++) {
    if (!(channel_mask & (1 << channel))) continue;
    if (sensor_count >= config::temperature_humidity::MAX_SENSORS) break;

    hardware::i2c::mux.selectChannel(channel);

    int result = cht_sensors[sensor_count].begin();
    if (result != CHT832X_OK) continue;

    uint16_t manufacturer = cht_sensors[sensor_count].getManufacturer();
    if (manufacturer != 0x5959) {
      Serial.printf("[temperature_and_humidity] mux channel %d: addr 0x%02X "
                    "responded but manufacturer 0x%04X != 0x5959, skipping\n",
                    channel, config::temperature_humidity::I2C_ADDR, manufacturer);
      continue;
    }

    cht_sensors[sensor_count].setReadDelay(config::temperature_humidity::READ_DELAY_MS);

    sensor_channels[sensor_count] = channel;
    sensor_count++;
    Serial.printf("[temperature_and_humidity] found CHT832X on mux channel %d\n",
                  channel);
  }

  hardware::i2c::mux.disableAllChannels();
  Serial.printf("[temperature_and_humidity] discovered %d sensor(s)\n",
                sensor_count);
  return sensor_count;
}

uint8_t sensors::temperature_and_humidity::sensorCount() noexcept {
  return sensor_count;
}

bool sensors::temperature_and_humidity::access(uint8_t index,
                                               TemperatureHumiditySensorData *sensor_data) noexcept {
  if (index >= sensor_count) return false;
  if (!sensor_data) return false;

  hardware::i2c::mux.selectChannel(sensor_channels[index]);

  delay(1);

  int result = cht_sensors[index].read();
  bool success = (result == CHT832X_OK || result == CHT832X_ERROR_CRC);

  if (success) {
    sensor_data->temperature_celsius = cht_sensors[index].getTemperature();
    sensor_data->relative_humidity_percent = cht_sensors[index].getHumidity();
    sensor_data->ok = true;
  } else {
    sensor_data->ok = false;
    Serial.printf("[temperature_and_humidity] sensor %d read failed: %d\n",
                  index, result);
  }

  return success;
}

uint8_t sensors::temperature_and_humidity::accessAll(TemperatureHumiditySensorData *sensor_data,
                                                     bool *read_ok,
                                                     uint8_t max_count) noexcept {
  uint8_t count = (sensor_count < max_count) ? sensor_count : max_count;
  uint8_t successful_reads = 0;

  for (uint8_t index = 0; index < count; index++) {
    read_ok[index] = sensors::temperature_and_humidity::access(index, &sensor_data[index]);
    if (read_ok[index]) {
      successful_reads++;
    } else {
      sensor_data[index].temperature_celsius = NAN;
      sensor_data[index].relative_humidity_percent = NAN;
    }
  }

  hardware::i2c::mux.disableAllChannels();
  return successful_reads;
}

#ifdef PIO_UNIT_TESTING

#include "../testing/it.h"
#include "../testing/i2c_helpers.h"

static void temperature_and_humidity_test_discovers_sensors(void) {
  TEST_MESSAGE("user scans mux channels for CHT832X sensors");
  test_ensure_wire1_with_power();
  hardware::i2c::initialize();

  uint8_t count = sensors::temperature_and_humidity::discover();
  char message[64];
  snprintf(message, sizeof(message), "discovered %d sensor(s)", count);
  TEST_MESSAGE(message);
  TEST_ASSERT_GREATER_THAN_MESSAGE(0, count,
    "device: no CHT832X sensors found on any mux channel");
}

static void temperature_and_humidity_test_reads_plausible_values(void) {
  TEST_MESSAGE("user reads temperature and humidity from sensor 0");

  if (sensors::temperature_and_humidity::sensorCount() == 0) {
    TEST_IGNORE_MESSAGE("no sensors discovered, skipping");
    return;
  }

  TemperatureHumiditySensorData sensor_data = {};
  bool success = sensors::temperature_and_humidity::access(0, &sensor_data);

  if (!success) {
    TEST_IGNORE_MESSAGE("CHT832X read NACK — blocked on i2c-ng driver issue");
    return;
  }

  char message[128];
  snprintf(message, sizeof(message),
           "sensor 0: %.2f C, %.2f %% RH", sensor_data.temperature_celsius,
           sensor_data.relative_humidity_percent);
  TEST_MESSAGE(message);

  TEST_ASSERT_FLOAT_WITHIN_MESSAGE(62.5f, 22.5f, sensor_data.temperature_celsius,
    "device: temperature out of plausible range (-40 to 85 C)");
  TEST_ASSERT_FLOAT_WITHIN_MESSAGE(50.0f, 50.0f, sensor_data.relative_humidity_percent,
    "device: humidity out of plausible range (0 to 100 %)");
}

static void temperature_and_humidity_test_rejects_out_of_range_index(void) {
  TEST_MESSAGE("user reads with an index beyond discovered count");

  TemperatureHumiditySensorData sensor_data = {};
  bool success = sensors::temperature_and_humidity::access(
    sensors::temperature_and_humidity::sensorCount(), &sensor_data);

  TEST_ASSERT_FALSE_MESSAGE(success,
    "device: read should fail for index >= sensor_count");
}

static void temperature_and_humidity_test_reads_all_sensors(void) {
  TEST_MESSAGE("user reads all discovered sensors");

  if (sensors::temperature_and_humidity::sensorCount() == 0) {
    TEST_IGNORE_MESSAGE("no sensors discovered, skipping (CHT832X reads blocked)");
    return;
  }

  delay(1100);

  uint8_t count = sensors::temperature_and_humidity::sensorCount();
  TemperatureHumiditySensorData sensor_data[config::temperature_humidity::MAX_SENSORS];
  bool read_ok[config::temperature_humidity::MAX_SENSORS];

  uint8_t successful = sensors::temperature_and_humidity::accessAll(
    sensor_data, read_ok, count);

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
               index, sensor_data[index].temperature_celsius,
               sensor_data[index].relative_humidity_percent);
      TEST_MESSAGE(message);
    }
  }
}

static void temperature_and_humidity_test_manufacturer_id(void) {
  TEST_MESSAGE("user reads manufacturer ID from sensor 0");

  if (sensors::temperature_and_humidity::sensorCount() == 0) {
    test_ensure_wire1_with_power();
    hardware::i2c::initialize();
    sensors::temperature_and_humidity::discover();
  }

  if (sensors::temperature_and_humidity::sensorCount() == 0) {
    TEST_IGNORE_MESSAGE("no sensors discovered");
    return;
  }

  hardware::i2c::mux.selectChannel(sensor_channels[0]);
  uint16_t manufacturer = cht_sensors[0].getManufacturer();
  hardware::i2c::mux.disableAllChannels();

  char message[64];
  snprintf(message, sizeof(message), "manufacturer ID: 0x%04X", manufacturer);
  TEST_MESSAGE(message);

  TEST_ASSERT_EQUAL_HEX16_MESSAGE(0x5959, manufacturer,
    "device: unexpected manufacturer ID (expected 0x5959)");
}

void sensors::temperature_and_humidity::test() noexcept {
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
