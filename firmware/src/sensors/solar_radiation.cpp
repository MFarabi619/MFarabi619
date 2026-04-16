#include "solar_radiation.h"
#include "registry.h"

#include <config.h>
#include "../hardware/rs485.h"
#include "../networking/modbus.h"

namespace {

bool available = false;

const config::ModbusSensorConfig *access_config() {
  for (size_t index = 0; index < config::modbus::DEVICE_COUNT; index++) {
    const config::ModbusSensorConfig &sensor_config = config::modbus::DEVICES[index];
    if (sensor_config.kind == config::ModbusSensorKind::SolarRadiation) {
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

bool sensors::solar_radiation::access(SolarRadiationSensorData *sensor_data) {
  if (!sensor_data) return false;
  sensor_data->watts_per_square_meter = 0;
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

  sensor_data->watts_per_square_meter = output_words[0];
  sensor_data->ok = true;
  return true;
}

bool sensors::solar_radiation::initialize() {
  if (!access_config()) {
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

#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

static void test_solar_radiation_config_lookup(void) {
  WHEN("the modbus topology is checked for solar radiation");

  const config::ModbusSensorConfig *cfg = nullptr;
  for (size_t i = 0; i < config::modbus::DEVICE_COUNT; i++) {
    if (config::modbus::DEVICES[i].kind == config::ModbusSensorKind::SolarRadiation) {
      cfg = &config::modbus::DEVICES[i];
      break;
    }
  }

  if (!cfg) {
    TEST_IGNORE_MESSAGE("no solar radiation sensor configured — skipping");
    return;
  }

  char msg[64];
  snprintf(msg, sizeof(msg), "channel=%d slave=%d register=%d",
           cfg->channel, cfg->slave_id, cfg->register_address);
  TEST_MESSAGE(msg);
}

static void test_solar_radiation_rejects_null(void) {
  WHEN("a null buffer is passed to access");
  THEN("it returns false");
  TEST_ASSERT_FALSE_MESSAGE(sensors::solar_radiation::access(nullptr),
      "device: access should fail with null pointer");
}

void sensors::solar_radiation::test() {
  RUN_TEST(test_solar_radiation_config_lookup);
  RUN_TEST(test_solar_radiation_rejects_null);
}

#endif
