#include "wind_direction.h"
#include "modbus_config.h"
#include "registry.h"

#include "../networking/modbus.h"

#include <math.h>

//--- state --------------------------------------------------------------------

static bool available = false;

//--- public API ---------------------------------------------------------------

bool sensors::wind_direction::access(WindDirectionSensorData *sensor_data) {
  if (!sensor_data) return false;
  sensor_data->degrees = NAN;
  sensor_data->slice = 0xFF;
  sensor_data->ok = false;
  const auto *device = find_modbus_device(config::ModbusSensorKind::WindDirection);
  if (!device) return false;

  uint16_t output_words[2] = {0, 0};
  ReadHoldingRegistersCommand command = {
    .channel = channel_for_device(device),
    .slave_id = device->slave_id,
    .start_register = device->register_address,
    .register_count = 2,
    .output_words = output_words,
    .error = ModbusError::NotInitialized,
  };

  if (!networking::modbus::readHoldingRegisters(&command)) return false;
  if (output_words[1] > 15) return false;

  sensor_data->degrees = output_words[0] / 10.0f;
  sensor_data->slice = static_cast<uint8_t>(output_words[1]);
  sensor_data->ok = true;
  return true;
}

bool sensors::wind_direction::initialize() {
  if (!find_modbus_device(config::ModbusSensorKind::WindDirection)) {
    available = false;
    return true;
  }
  WindDirectionSensorData sensor_data = {};
  available = sensors::wind_direction::access(&sensor_data);
  if (available) {
    sensors::registry::add({
        .kind = SensorKind::WindDirection,
        .name = "Wind Direction",
        .isAvailable = sensors::wind_direction::isAvailable,
        .instanceCount = []() -> uint8_t { return 1; },
        .poll = [](uint8_t, void *out, size_t cap) -> bool {
            if (cap < sizeof(WindDirectionSensorData)) return false;
            return sensors::wind_direction::access(
                static_cast<WindDirectionSensorData *>(out));
        },
        .data_size = sizeof(WindDirectionSensorData),
    });
  }
  return available;
}

bool sensors::wind_direction::isAvailable() {
  return available;
}

//--- tests --------------------------------------------------------------------

#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

static void test_wind_direction_config(void) {
  GIVEN("wind direction sensor config");
  THEN("the device entry exists in the config array");

  const auto *device = find_modbus_device(config::ModbusSensorKind::WindDirection);
  if (!device) {
    TEST_IGNORE_MESSAGE("no wind direction sensor configured — skipping");
    return;
  }

  char msg[64];
  snprintf(msg, sizeof(msg), "channel=%d slave=%d register=%d",
           device->channel, device->slave_id, device->register_address);
  TEST_MESSAGE(msg);
}

static void test_wind_direction_rejects_null(void) {
  WHEN("a null buffer is passed to access");
  THEN("it returns false");
  TEST_ASSERT_FALSE_MESSAGE(sensors::wind_direction::access(nullptr),
      "device: access should fail with null pointer");
}

static void test_wind_direction_read(void) {
  WHEN("wind direction sensor is polled");
  THEN("access returns a valid reading or fails gracefully");

  WindDirectionSensorData sensor_data = {};
  bool ok = sensors::wind_direction::access(&sensor_data);
  if (ok) {
    TEST_ASSERT_TRUE_MESSAGE(sensor_data.ok, "device: ok flag should be set");
    TEST_ASSERT_FALSE_MESSAGE(isnan(sensor_data.degrees),
      "device: degrees should not be NaN on successful read");
    TEST_ASSERT_TRUE_MESSAGE(sensor_data.slice <= 15,
      "device: slice must be 0-15");
    char msg[64];
    snprintf(msg, sizeof(msg), "wind direction: %.1f deg slice %d",
             sensor_data.degrees, sensor_data.slice);
    TEST_MESSAGE(msg);
  } else {
    TEST_IGNORE_MESSAGE("skipped — wind direction sensor not responding on bus");
  }
}

void sensors::wind_direction::test(void) {
  MODULE("Wind Direction");
  RUN_TEST(test_wind_direction_config);
  RUN_TEST(test_wind_direction_rejects_null);
  RUN_TEST(test_wind_direction_read);
}

#endif
