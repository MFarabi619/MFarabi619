#include "rainfall.h"
#include "registry.h"

#include <config.h>
#include "../hardware/rs485.h"
#include "../networking/modbus.h"

#include <math.h>

namespace {

bool available = false;

const config::ModbusSensorConfig *access_config() {
  for (size_t index = 0; index < config::modbus::DEVICE_COUNT; index++) {
    const config::ModbusSensorConfig &sensor_config = config::modbus::DEVICES[index];
    if (sensor_config.kind == config::ModbusSensorKind::Rain) {
      return &sensor_config;
    }
  }
  return nullptr;
}

hardware::rs485::Channel channel_from_config(const config::ModbusSensorConfig *sensor_config) {
  return sensor_config && sensor_config->channel == 0
      ? hardware::rs485::Channel::Bus0
      : hardware::rs485::Channel::Bus1;
}

}

bool sensors::rainfall::access(RainfallSensorData *sensor_data) {
  if (!sensor_data) return false;
  sensor_data->millimeters = NAN;
  sensor_data->ok = false;
  const config::ModbusSensorConfig *sensor_config = access_config();
  if (!sensor_config) return false;

  uint16_t output_words[1] = {0};
  ReadHoldingRegistersCommand command = {
    .channel = channel_from_config(sensor_config),
    .slave_id = sensor_config->slave_id,
    .start_register = sensor_config->register_address,
    .register_count = 1,
    .output_words = output_words,
    .error = ModbusError::NotInitialized,
  };

  if (!networking::modbus::readHoldingRegisters(&command)) return false;

  sensor_data->millimeters = output_words[0] / 10.0f;
  sensor_data->ok = true;
  return true;
}

bool sensors::rainfall::clear() {
  const config::ModbusSensorConfig *sensor_config = access_config();
  if (!sensor_config) return false;

  WriteSingleRegisterCommand command = {
    .channel = channel_from_config(sensor_config),
    .slave_id = sensor_config->slave_id,
    .register_address = 0x0000,
    .value = 0x005A,
    .error = ModbusError::NotInitialized,
  };

  return networking::modbus::writeSingleRegister(&command);
}

bool sensors::rainfall::initialize() {
  if (!access_config()) {
    available = false;
    return true;
  }
  RainfallSensorData sensor_data = {};
  available = sensors::rainfall::access(&sensor_data);
  if (available) {
    sensors::registry::add({
        .kind = SensorKind::Rain,
        .name = "Rainfall",
        .isAvailable = sensors::rainfall::isAvailable,
        .instanceCount = []() -> uint8_t { return 1; },
        .poll = [](uint8_t, void *out, size_t cap) -> bool {
            if (cap < sizeof(RainfallSensorData)) return false;
            return sensors::rainfall::access(
                static_cast<RainfallSensorData *>(out));
        },
        .data_size = sizeof(RainfallSensorData),
    });
  }
  return available;
}

bool sensors::rainfall::isAvailable() {
  return available;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

namespace sensors::rainfall { void test(void); }

static void test_rainfall_config(void) {
  GIVEN("rainfall sensor config");
  THEN("the device entry exists in the config array");

  bool found = false;
  for (size_t index = 0; index < config::modbus::DEVICE_COUNT; index++) {
    if (config::modbus::DEVICES[index].kind == config::ModbusSensorKind::Rain) {
      found = true;
      TEST_ASSERT_EQUAL_MESSAGE(0, config::modbus::DEVICES[index].channel,
        "device: rain sensor should be on Bus 0 (9600 baud)");
      break;
    }
  }
  TEST_ASSERT_TRUE_MESSAGE(found, "device: Rain entry missing from modbus::DEVICES");
}

static void test_rainfall_read(void) {
  WHEN("rainfall sensor is polled");
  THEN("access returns a valid reading or fails gracefully");

  RainfallSensorData sensor_data = {};
  bool ok = sensors::rainfall::access(&sensor_data);
  if (ok) {
    TEST_ASSERT_TRUE_MESSAGE(sensor_data.ok, "device: ok flag should be set");
    TEST_ASSERT_FALSE_MESSAGE(isnan(sensor_data.millimeters),
      "device: millimeters should not be NaN on successful read");
    char msg[64];
    snprintf(msg, sizeof(msg), "rainfall: %.1f mm", sensor_data.millimeters);
    TEST_MESSAGE(msg);
  } else {
    TEST_IGNORE_MESSAGE("skipped — rain sensor not responding on bus");
  }
}

void sensors::rainfall::test(void) {
  MODULE("Rainfall");
  RUN_TEST(test_rainfall_config);
  RUN_TEST(test_rainfall_read);
}

#endif
