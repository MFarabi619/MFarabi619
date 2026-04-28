#include "solar_radiation.h"
#include "modbus_config.h"
#include "registry.h"

#include "../networking/modbus.h"

//--- state --------------------------------------------------------------------

static bool available = false;

//--- public API ---------------------------------------------------------------

bool sensors::solar_radiation::access(SolarRadiationSensorData *sensor_data) {
  if (!sensor_data) return false;
  sensor_data->watts_per_square_meter = 0;
  sensor_data->ok = false;
  const auto *device = find_modbus_device(config::ModbusSensorKind::SolarRadiation);
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

  sensor_data->watts_per_square_meter = output_words[0];
  sensor_data->ok = true;
  return true;
}

bool sensors::solar_radiation::initialize() {
  if (!find_modbus_device(config::ModbusSensorKind::SolarRadiation)) {
    available = false;
    return true;
  }
  SolarRadiationSensorData sensor_data = {};
  available = sensors::solar_radiation::access(&sensor_data);
  if (available) {
    sensors::registry::add({
        .kind = SensorKind::SolarRadiation,
        .name = "Solar Radiation",
        .isAvailable = sensors::solar_radiation::isAvailable,
        .instanceCount = []() -> uint8_t { return 1; },
        .poll = [](uint8_t, void *out, size_t cap) -> bool {
            if (cap < sizeof(SolarRadiationSensorData)) return false;
            return sensors::solar_radiation::access(
                static_cast<SolarRadiationSensorData *>(out));
        },
        .data_size = sizeof(SolarRadiationSensorData),
    });
  }
  return available;
}

bool sensors::solar_radiation::isAvailable() {
  return available;
}

//--- tests --------------------------------------------------------------------

#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

static void test_solar_radiation_config_lookup(void) {
  WHEN("the modbus topology is checked for solar radiation");

  const auto *device = find_modbus_device(config::ModbusSensorKind::SolarRadiation);
  if (!device) {
    TEST_IGNORE_MESSAGE("no solar radiation sensor configured — skipping");
    return;
  }

  char msg[64];
  snprintf(msg, sizeof(msg), "channel=%d slave=%d register=%d",
           device->channel, device->slave_id, device->register_address);
  TEST_MESSAGE(msg);
}

static void test_solar_radiation_rejects_null(void) {
  WHEN("a null buffer is passed to access");
  THEN("it returns false");
  TEST_ASSERT_FALSE_MESSAGE(sensors::solar_radiation::access(nullptr),
      "device: access should fail with null pointer");
}

void sensors::solar_radiation::test() {
  MODULE("Solar Radiation");
  RUN_TEST(test_solar_radiation_config_lookup);
  RUN_TEST(test_solar_radiation_rejects_null);
}

#endif
