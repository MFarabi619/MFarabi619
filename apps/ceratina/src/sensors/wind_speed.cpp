#include "wind_speed.h"
#include "modbus_config.h"
#include "registry.h"

#include "../networking/modbus.h"

#include <math.h>

//--- state --------------------------------------------------------------------

static bool available = false;

//--- public API ---------------------------------------------------------------

bool sensors::wind_speed::access(WindSpeedSensorData *sensor_data) {
  if (!sensor_data) return false;
  sensor_data->kilometers_per_hour = NAN;
  sensor_data->ok = false;
  const auto *device = find_modbus_device(config::ModbusSensorKind::WindSpeed);
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

  sensor_data->kilometers_per_hour = (output_words[0] * 3.6f) / 10.0f;
  sensor_data->ok = true;
  return true;
}

bool sensors::wind_speed::initialize() {
  if (!find_modbus_device(config::ModbusSensorKind::WindSpeed)) {
    available = false;
    return true;
  }
  WindSpeedSensorData sensor_data = {};
  available = sensors::wind_speed::access(&sensor_data);
  if (available) {
    sensors::registry::add({
        .kind = SensorKind::WindSpeed,
        .name = "Wind Speed",
        .isAvailable = sensors::wind_speed::isAvailable,
        .instanceCount = []() -> uint8_t { return 1; },
        .poll = [](uint8_t, void *out, size_t cap) -> bool {
            if (cap < sizeof(WindSpeedSensorData)) return false;
            return sensors::wind_speed::access(
                static_cast<WindSpeedSensorData *>(out));
        },
        .data_size = sizeof(WindSpeedSensorData),
    });
  }
  return available;
}

bool sensors::wind_speed::isAvailable() {
  return available;
}

//--- tests --------------------------------------------------------------------

#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

static void test_wind_speed_config(void) {
  GIVEN("wind speed sensor config");
  THEN("the device entry exists in the config array");

  const auto *device = find_modbus_device(config::ModbusSensorKind::WindSpeed);
  if (!device) {
    TEST_IGNORE_MESSAGE("no wind speed sensor configured — skipping");
    return;
  }

  char msg[64];
  snprintf(msg, sizeof(msg), "channel=%d slave=%d register=%d",
           device->channel, device->slave_id, device->register_address);
  TEST_MESSAGE(msg);
}

static void test_wind_speed_rejects_null(void) {
  WHEN("a null buffer is passed to access");
  THEN("it returns false");
  TEST_ASSERT_FALSE_MESSAGE(sensors::wind_speed::access(nullptr),
      "device: access should fail with null pointer");
}

static void test_wind_speed_read(void) {
  WHEN("wind speed sensor is polled");
  THEN("access returns a valid reading or fails gracefully");

  WindSpeedSensorData sensor_data = {};
  bool ok = sensors::wind_speed::access(&sensor_data);
  if (ok) {
    TEST_ASSERT_TRUE_MESSAGE(sensor_data.ok, "device: ok flag should be set");
    TEST_ASSERT_FALSE_MESSAGE(isnan(sensor_data.kilometers_per_hour),
      "device: km/h should not be NaN on successful read");
    char msg[64];
    snprintf(msg, sizeof(msg), "wind speed: %.1f km/h", sensor_data.kilometers_per_hour);
    TEST_MESSAGE(msg);
  } else {
    TEST_IGNORE_MESSAGE("skipped — wind speed sensor not responding on bus");
  }
}

void sensors::wind_speed::test(void) {
  MODULE("Wind Speed");
  RUN_TEST(test_wind_speed_config);
  RUN_TEST(test_wind_speed_rejects_null);
  RUN_TEST(test_wind_speed_read);
}

#endif
