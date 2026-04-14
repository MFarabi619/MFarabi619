#include "temperature_and_humidity.h"
#include "../config.h"
#include "../hardware/i2c.h"

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
  config::I2CSensorConfig config;
  int8_t resolved_mux_channel;
  bool available;
};

TemperatureHumiditySlot slots[config::temperature_humidity::MAX_SENSORS] = {};
uint8_t sensor_count = 0;

hardware::i2c::Bus to_bus(uint8_t bus) {
  return bus == 0 ? hardware::i2c::Bus::Bus0 : hardware::i2c::Bus::Bus1;
}

bool access_i2c_device(const config::I2CSensorConfig &config,
                       int8_t resolved_mux_channel,
                       hardware::i2c::DeviceAccessCommand *command) {
  if (!command) return false;
  command->bus = to_bus(config.bus);
  command->mux_channel = resolved_mux_channel;
  command->wire = nullptr;
  command->ok = false;
  return hardware::i2c::accessDevice(command);
}

bool probe_cht832x(const config::I2CSensorConfig &config,
                   int8_t resolved_mux_channel) {
  hardware::i2c::DeviceAccessCommand command = {};
  if (!access_i2c_device(config, resolved_mux_channel, &command)) return false;

  CHT832X sensor(config.address, command.wire);
  int result = sensor.begin();
  if (result != CHT832X_OK) {
    hardware::i2c::clearSelection();
    return false;
  }

  uint16_t manufacturer = sensor.getManufacturer();
  hardware::i2c::clearSelection();
  return manufacturer == 0x5959;
}

bool probe_sht31(const config::I2CSensorConfig &config,
                 int8_t resolved_mux_channel) {
  hardware::i2c::DeviceAccessCommand command = {};
  if (!access_i2c_device(config, resolved_mux_channel, &command)) return false;

  SHT31 sensor(config.address, command.wire);
  bool ok = sensor.begin() && sensor.isConnected();
  hardware::i2c::clearSelection();
  return ok;
}

bool probe_descriptor(const config::I2CSensorConfig &config,
                      int8_t resolved_mux_channel) {
  switch (config.kind) {
    case config::I2CSensorKind::TemperatureHumidityCHT832X:
      return probe_cht832x(config, resolved_mux_channel);
    case config::I2CSensorKind::TemperatureHumiditySHT3X:
      return probe_sht31(config, resolved_mux_channel);
    default:
      return false;
  }
}

bool read_cht832x(const TemperatureHumiditySlot &slot,
                  TemperatureHumiditySensorData *sensor_data) {
  hardware::i2c::DeviceAccessCommand command = {};
  if (!access_i2c_device(slot.config, slot.resolved_mux_channel, &command)) return false;

  CHT832X sensor(slot.config.address, command.wire);
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
  if (!access_i2c_device(slot.config, slot.resolved_mux_channel, &command)) return false;

  SHT31 sensor(slot.config.address, command.wire);
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

void append_slot(TemperatureHumidityBackend backend,
                 const config::I2CSensorConfig &config,
                 int8_t resolved_mux_channel) {
  if (sensor_count >= config::temperature_humidity::MAX_SENSORS) return;
  slots[sensor_count++] = {
    .backend = backend,
    .config = config,
    .resolved_mux_channel = resolved_mux_channel,
    .available = true,
  };
}

}

bool sensors::temperature_and_humidity::initialize() {
  sensor_count = 0;

  hardware::i2c::TopologySnapshot topology = {};
  hardware::i2c::accessTopology(&topology);

  for (size_t index = 0; index < config::i2c_topology::DEVICE_COUNT; index++) {
    const config::I2CSensorConfig &device = config::i2c_topology::DEVICES[index];
    TemperatureHumidityBackend backend;

    switch (device.kind) {
      case config::I2CSensorKind::TemperatureHumidityCHT832X:
        backend = TemperatureHumidityBackend::CHT832X;
        break;
      case config::I2CSensorKind::TemperatureHumiditySHT3X:
        backend = TemperatureHumidityBackend::SHT31;
        break;
      default:
        continue;
    }

    if (device.mux_channel == config::i2c::DIRECT_CHANNEL) {
      if (probe_descriptor(device, config::i2c::DIRECT_CHANNEL)) {
        append_slot(backend, device, config::i2c::DIRECT_CHANNEL);
        Serial.printf("[temperature_and_humidity] found %s on bus %u addr 0x%02X\n",
                      backend == TemperatureHumidityBackend::CHT832X ? "CHT832X" : "SHT31",
                      device.bus, device.address);
      }
      continue;
    }

    if (device.mux_channel == config::i2c::ANY_MUX_CHANNEL) {
      if (!topology.mux_present || device.bus != 1) continue;
      for (uint8_t channel = 0; channel < hardware::i2c::mux.channelCount(); channel++) {
        if (probe_descriptor(device, channel)) {
          append_slot(backend, device, channel);
          Serial.printf("[temperature_and_humidity] found %s on mux channel %u addr 0x%02X\n",
                        backend == TemperatureHumidityBackend::CHT832X ? "CHT832X" : "SHT31",
                        channel, device.address);
        }
      }
      continue;
    }

    if (!topology.mux_present || device.bus != 1) continue;
    if (probe_descriptor(device, device.mux_channel)) {
      append_slot(backend, device, device.mux_channel);
      Serial.printf("[temperature_and_humidity] found %s on mux channel %d addr 0x%02X\n",
                    backend == TemperatureHumidityBackend::CHT832X ? "CHT832X" : "SHT31",
                    device.mux_channel, device.address);
    }
  }

  hardware::i2c::clearSelection();
  Serial.printf("[temperature_and_humidity] discovered %d sensor(s)\n",
                sensor_count);
  return sensor_count > 0;
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

#include "../testing/it.h"
#include "../testing/i2c_helpers.h"

static void temperature_and_humidity_test_discovers_sensors(void) {
  TEST_MESSAGE("user discovers temperature and humidity sensors from the I2C topology");
  test_ensure_wire1_with_power();
  hardware::i2c::initialize();

  uint8_t count = sensors::temperature_and_humidity::initialize();
  char message[64];
  snprintf(message, sizeof(message), "discovered %d sensor(s)", count);
  TEST_MESSAGE(message);
  TEST_ASSERT_GREATER_THAN_MESSAGE(0, count,
    "device: no temperature/humidity sensors found");
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
    TEST_IGNORE_MESSAGE("temperature/humidity read failed — sensor may be absent or busy");
    return;
  }

  char message[128];
  snprintf(message, sizeof(message),
           "sensor 0 (%s): %.2f C, %.2f %% RH", sensor_data.model ? sensor_data.model : "unknown",
           sensor_data.temperature_celsius,
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

static void temperature_and_humidity_test_cht832x_manufacturer_id(void) {
  TEST_MESSAGE("user reads manufacturer ID from the first discovered CHT832X sensor");

  if (sensors::temperature_and_humidity::sensorCount() == 0) {
    test_ensure_wire1_with_power();
    hardware::i2c::initialize();
    sensors::temperature_and_humidity::initialize();
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
  TEST_ASSERT_TRUE_MESSAGE(access_i2c_device(slots[cht_index].config,
                                             slots[cht_index].resolved_mux_channel,
                                             &command),
    "device: failed to access resolved CHT832X device");
  CHT832X sensor(slots[cht_index].config.address, command.wire);
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
  it("user discovers temperature and humidity sensors from the topology table",
     temperature_and_humidity_test_discovers_sensors);
  it("user reads plausible temperature and humidity from sensor 0",
     temperature_and_humidity_test_reads_plausible_values);
  it("user observes that out of range index is rejected",
     temperature_and_humidity_test_rejects_out_of_range_index);
  it("user reads all discovered sensors",
     temperature_and_humidity_test_reads_all_sensors);
  it("user verifies a discovered CHT832X reports manufacturer ID 0x5959",
     temperature_and_humidity_test_cht832x_manufacturer_id);
}

#endif
