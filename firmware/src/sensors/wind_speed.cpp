#include "wind_speed.h"
#include "registry.h"

#include "../config.h"
#include "../hardware/rs485.h"
#include "../networking/modbus.h"

#include <math.h>

namespace {

bool available = false;

const config::ModbusSensorConfig *access_config() {
  for (size_t index = 0; index < config::modbus::DEVICE_COUNT; index++) {
    const config::ModbusSensorConfig &sensor_config = config::modbus::DEVICES[index];
    if (sensor_config.kind == config::ModbusSensorKind::WindSpeed) {
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

bool sensors::wind_speed::access(WindSpeedSensorData *sensor_data) {
  if (!sensor_data) return false;
  sensor_data->kilometers_per_hour = NAN;
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

  sensor_data->kilometers_per_hour = (output_words[0] * 3.6f) / 10.0f;
  sensor_data->ok = true;
  return true;
}

bool sensors::wind_speed::initialize() {
  if (!access_config()) {
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
