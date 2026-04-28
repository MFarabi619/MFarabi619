#include "rainfall.h"
#include "modbus_config.h"
#include "registry.h"

#include "../networking/modbus.h"

#include <math.h>

//--- state --------------------------------------------------------------------

static bool available = false;

//--- public API ---------------------------------------------------------------

bool sensors::rainfall::access(RainfallSensorData *sensor_data) {
  if (!sensor_data) return false;
  sensor_data->millimeters = NAN;
  sensor_data->ok = false;
  const auto *device = find_modbus_device(config::ModbusSensorKind::Rain);
  if (!device) return false;

  uint16_t output_words[1] = {0};
  ReadHoldingRegistersCommand command = {
    .channel = channel_for_device(device),
    .slave_id = device->slave_id,
    .start_register = device->register_address,
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
  const auto *device = find_modbus_device(config::ModbusSensorKind::Rain);
  if (!device) return false;

  WriteSingleRegisterCommand command = {
    .channel = channel_for_device(device),
    .slave_id = device->slave_id,
    .register_address = config::rainfall::CLEAR_REGISTER,
    .value = config::rainfall::CLEAR_VALUE,
    .error = ModbusError::NotInitialized,
  };

  return networking::modbus::writeSingleRegister(&command);
}

bool sensors::rainfall::initialize() {
  if (!find_modbus_device(config::ModbusSensorKind::Rain)) {
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

//--- tests --------------------------------------------------------------------

#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

static void test_rainfall_config(void) {
  GIVEN("rainfall sensor config");
  THEN("the device entry exists in the config array");

  const auto *device = find_modbus_device(config::ModbusSensorKind::Rain);
  if (!device) {
    TEST_IGNORE_MESSAGE("no rain sensor configured — skipping");
    return;
  }

  TEST_ASSERT_EQUAL_MESSAGE(0, device->channel,
    "device: rain sensor should be on Bus 0");

  char msg[64];
  snprintf(msg, sizeof(msg), "channel=%d slave=%d register=%d",
           device->channel, device->slave_id, device->register_address);
  TEST_MESSAGE(msg);
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
