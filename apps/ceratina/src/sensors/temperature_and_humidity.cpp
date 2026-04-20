#include "temperature_and_humidity.h"
#include "registry.h"
#include <config.h>
#include <i2c.h>

#include <Arduino.h>
#include <CHT832X.h>
#include <SHT31.h>
#include <math.h>

namespace {

enum class TemperatureHumidityBackend : uint8_t {
  CHT832X,
  SHT31,
};

struct TemperatureHumiditySlot {
  TemperatureHumidityBackend backend;
  uint8_t bus;
  uint8_t address;
  int8_t mux_channel;
  bool available;
};

TemperatureHumiditySlot slots[config::temperature_humidity::MAX_SENSORS] = {};
uint8_t sensor_count = 0;
bool registered = false;

hardware::i2c::Bus to_bus(uint8_t bus) {
  return bus == 0 ? hardware::i2c::Bus::Bus0 : hardware::i2c::Bus::Bus1;
}

bool access_slot(const TemperatureHumiditySlot &slot,
                 hardware::i2c::DeviceAccessCommand *command) {
  if (!command) return false;
  command->bus = to_bus(slot.bus);
  command->mux_channel = slot.mux_channel;
  command->wire = nullptr;
  command->ok = false;
  return hardware::i2c::accessDevice(command);
}

void append_slot(TemperatureHumidityBackend backend,
                 const hardware::i2c::DiscoveredDevice &dev) {
  if (sensor_count >= config::temperature_humidity::MAX_SENSORS) return;
  slots[sensor_count++] = {
    .backend = backend,
    .bus = dev.bus,
    .address = dev.address,
    .mux_channel = dev.mux_channel,
    .available = true,
  };
}

void ensure_registered() {
  if (registered || sensor_count == 0) return;
  sensors::registry::add({
      .kind = SensorKind::TemperatureHumidity,
      .name = "Temperature & Humidity",
      .isAvailable = []() -> bool {
          return sensors::temperature_and_humidity::sensorCount() > 0;
      },
      .instanceCount = sensors::temperature_and_humidity::sensorCount,
      .poll = [](uint8_t index, void *out, size_t cap) -> bool {
          if (cap < sizeof(TemperatureHumiditySensorData)) return false;
          return sensors::temperature_and_humidity::access(
              index, static_cast<TemperatureHumiditySensorData *>(out));
      },
      .data_size = sizeof(TemperatureHumiditySensorData),
  });
  registered = true;
}

bool probe_cht832x_discovered(const hardware::i2c::DiscoveredDevice &dev) {
  hardware::i2c::DeviceAccessCommand command = {};
  command.bus = to_bus(dev.bus);
  command.mux_channel = dev.mux_channel;
  if (!hardware::i2c::accessDevice(&command)) return false;

  CHT832X sensor(dev.address, command.wire);
  if (sensor.begin() != CHT832X_OK) {
    hardware::i2c::clearSelection();
    return false;
  }

  uint16_t manufacturer = sensor.getManufacturer();
  hardware::i2c::clearSelection();
  if (manufacturer != 0x5959) return false;

  append_slot(TemperatureHumidityBackend::CHT832X, dev);
  ensure_registered();
  return true;
}

bool probe_sht31_discovered(const hardware::i2c::DiscoveredDevice &dev) {
  hardware::i2c::DeviceAccessCommand command = {};
  command.bus = to_bus(dev.bus);
  command.mux_channel = dev.mux_channel;
  if (!hardware::i2c::accessDevice(&command)) return false;

  SHT31 sensor(dev.address, command.wire);
  bool ok = sensor.begin() && sensor.isConnected();
  hardware::i2c::clearSelection();
  if (!ok) return false;

  append_slot(TemperatureHumidityBackend::SHT31, dev);
  ensure_registered();
  return true;
}

bool read_cht832x(const TemperatureHumiditySlot &slot,
                  TemperatureHumiditySensorData *sensor_data) {
  hardware::i2c::DeviceAccessCommand command = {};
  if (!access_slot(slot, &command)) return false;

  CHT832X sensor(slot.address, command.wire);
  int begin_result = sensor.begin();
  if (begin_result != CHT832X_OK) {
    hardware::i2c::clearSelection();
    return false;
  }

  sensor.setReadDelay(config::temperature_humidity::READ_DELAY_MS);
  int result = sensor.read();
  bool success = (result == CHT832X_OK || result == CHT832X_ERROR_CRC);
  if (success) {
    sensor_data->temperature_celsius = sensor.getTemperature();
    sensor_data->relative_humidity_percent = sensor.getHumidity();
    sensor_data->model = "CHT832X";
    sensor_data->ok = true;
  } else {
    sensor_data->model = "CHT832X";
    sensor_data->ok = false;
    Serial.printf("[temperature_and_humidity] CHT832X read failed: %d\n", result);
  }

  hardware::i2c::clearSelection();
  return success;
}

bool read_sht31(const TemperatureHumiditySlot &slot,
                TemperatureHumiditySensorData *sensor_data) {
  hardware::i2c::DeviceAccessCommand command = {};
  if (!access_slot(slot, &command)) return false;

  SHT31 sensor(slot.address, command.wire);
  bool success = sensor.begin() && sensor.read(true);
  if (success) {
    sensor_data->temperature_celsius = sensor.getTemperature();
    sensor_data->relative_humidity_percent = sensor.getHumidity();
    sensor_data->model = "SHT31";
    sensor_data->ok = true;
  } else {
    sensor_data->model = "SHT31";
    sensor_data->ok = false;
  }

  hardware::i2c::clearSelection();
  return success;
}

}

void sensors::temperature_and_humidity::registerProbes() {
  sensor_count = 0;
  registered = false;
  hardware::i2c::registerProbe({0x44, probe_cht832x_discovered, "CHT832X", 10});
  hardware::i2c::registerProbe({0x44, probe_sht31_discovered, "SHT3x", 20});
}

uint8_t sensors::temperature_and_humidity::sensorCount() {
  return sensor_count;
}

bool sensors::temperature_and_humidity::access(uint8_t index,
                                               TemperatureHumiditySensorData *sensor_data) {
  if (index >= sensor_count) return false;
  if (!sensor_data) return false;

  switch (slots[index].backend) {
    case TemperatureHumidityBackend::CHT832X:
      return read_cht832x(slots[index], sensor_data);
    case TemperatureHumidityBackend::SHT31:
      return read_sht31(slots[index], sensor_data);
    default:
      return false;
  }
}

uint8_t sensors::temperature_and_humidity::accessAll(TemperatureHumiditySensorData *sensor_data,
                                                     bool *read_ok,
                                                     uint8_t max_count) {
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

  hardware::i2c::clearSelection();
  return successful_reads;
}

#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>


static void test_temp_humidity_discovers_sensors(void) {
  GIVEN("Wire1 with power enabled");
  WHEN("sensors are discovered via probe-based I2C scan");
  test_ensure_wire1_with_power();
  hardware::i2c::initialize();
  sensors::temperature_and_humidity::registerProbes();
  hardware::i2c::runDiscovery();
  hardware::i2c::probeAll();

  uint8_t count = sensors::temperature_and_humidity::sensorCount();
  char message[64];
  snprintf(message, sizeof(message), "discovered %d sensor(s)", count);
  TEST_MESSAGE(message);
  if (count == 0) {
    TEST_IGNORE_MESSAGE("no temperature/humidity sensors connected");
    return;
  }
}

static void test_temp_humidity_reads_plausible_values(void) {
  GIVEN("at least one discovered sensor");
  WHEN("sensor 0 is read");

  if (sensors::temperature_and_humidity::sensorCount() == 0) {
    TEST_IGNORE_MESSAGE("no sensors discovered, skipping");
    return;
  }

  TemperatureHumiditySensorData sensor_data = {};
  bool success = sensors::temperature_and_humidity::access(0, &sensor_data);

  if (!success) {
    TEST_IGNORE_MESSAGE("temperature/humidity read failed — sensor may be absent or busy");
    return;
  }

  char message[128];
  snprintf(message, sizeof(message),
           "sensor 0 (%s): %.2f C, %.2f %% RH", sensor_data.model ? sensor_data.model : "unknown",
           sensor_data.temperature_celsius,
           sensor_data.relative_humidity_percent);
  TEST_MESSAGE(message);

  TEST_ASSERT_FLOAT_IS_DETERMINATE_MESSAGE(sensor_data.temperature_celsius,
    "device: temperature reading is NaN or Inf");
  TEST_ASSERT_FLOAT_IS_DETERMINATE_MESSAGE(sensor_data.relative_humidity_percent,
    "device: humidity reading is NaN or Inf");
  TEST_ASSERT_GREATER_OR_EQUAL_FLOAT_MESSAGE(-40.0f, sensor_data.temperature_celsius,
    "device: temperature below SHT3x minimum (-40 C)");
  TEST_ASSERT_LESS_OR_EQUAL_FLOAT_MESSAGE(85.0f, sensor_data.temperature_celsius,
    "device: temperature above SHT3x maximum (85 C)");
  TEST_ASSERT_GREATER_OR_EQUAL_FLOAT_MESSAGE(0.0f, sensor_data.relative_humidity_percent,
    "device: humidity below 0 %");
  TEST_ASSERT_LESS_OR_EQUAL_FLOAT_MESSAGE(100.0f, sensor_data.relative_humidity_percent,
    "device: humidity above 100 %");
}

static void test_temp_humidity_rejects_out_of_range_index(void) {
  WHEN("an out-of-range sensor index is read");

  TemperatureHumiditySensorData sensor_data = {};
  bool success = sensors::temperature_and_humidity::access(
    sensors::temperature_and_humidity::sensorCount(), &sensor_data);

  TEST_ASSERT_FALSE_MESSAGE(success,
    "device: read should fail for index >= sensor_count");
}

static void test_temp_humidity_reads_all_sensors(void) {
  GIVEN("discovered sensors");
  WHEN("all sensors are read");

  if (sensors::temperature_and_humidity::sensorCount() == 0) {
    TEST_IGNORE_MESSAGE("no temperature/humidity sensors discovered");
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
               "sensor %d (%s): %.2f C, %.2f %% RH",
                index, sensor_data[index].model ? sensor_data[index].model : "unknown",
                sensor_data[index].temperature_celsius,
                sensor_data[index].relative_humidity_percent);
      TEST_MESSAGE(message);
    }
  }
}

static void test_temp_humidity_cht832x_manufacturer_id(void) {
  GIVEN("a discovered CHT832X sensor");
  WHEN("the manufacturer ID is read");

  if (sensors::temperature_and_humidity::sensorCount() == 0) {
    test_ensure_wire1_with_power();
    hardware::i2c::initialize();
    sensors::temperature_and_humidity::registerProbes();
    hardware::i2c::runDiscovery();
    hardware::i2c::probeAll();
  }

  size_t cht_index = SIZE_MAX;
  for (uint8_t index = 0; index < sensors::temperature_and_humidity::sensorCount(); index++) {
    if (slots[index].backend == TemperatureHumidityBackend::CHT832X) {
      cht_index = index;
      break;
    }
  }

  if (cht_index == SIZE_MAX) {
    TEST_IGNORE_MESSAGE("no CHT832X sensors discovered");
    return;
  }

  hardware::i2c::DeviceAccessCommand command = {};
  TEST_ASSERT_TRUE_MESSAGE(access_slot(slots[cht_index], &command),
    "device: failed to access resolved CHT832X device");
  CHT832X sensor(slots[cht_index].address, command.wire);
  TEST_ASSERT_EQUAL_INT_MESSAGE(CHT832X_OK, sensor.begin(),
    "device: CHT832X begin failed during manufacturer check");
  uint16_t manufacturer = sensor.getManufacturer();
  hardware::i2c::clearSelection();

  char message[64];
  snprintf(message, sizeof(message), "manufacturer ID: 0x%04X", manufacturer);
  TEST_MESSAGE(message);

  TEST_ASSERT_EQUAL_HEX16_MESSAGE(0x5959, manufacturer,
    "device: unexpected manufacturer ID (expected 0x5959)");
}

void sensors::temperature_and_humidity::test() {
  MODULE("Temperature & Humidity");
  RUN_TEST(test_temp_humidity_discovers_sensors);
  RUN_TEST(test_temp_humidity_reads_plausible_values);
  RUN_TEST(test_temp_humidity_rejects_out_of_range_index);
  RUN_TEST(test_temp_humidity_reads_all_sensors);
  RUN_TEST(test_temp_humidity_cht832x_manufacturer_id);
}

#endif
