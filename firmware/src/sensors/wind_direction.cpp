#include "wind_direction.h"
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
    if (sensor_config.kind == config::ModbusSensorKind::WindDirection) {
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

bool sensors::wind_direction::access(WindDirectionSensorData *sensor_data) {
  if (!sensor_data) return false;
  sensor_data->degrees = NAN;
  sensor_data->slice = 0xFF;
  sensor_data->ok = false;
  const config::ModbusSensorConfig *sensor_config = access_config();
  if (!sensor_config) return false;

  uint16_t output_words[2] = {0, 0};
  ReadHoldingRegistersCommand command = {
    .channel = channel_from_config(sensor_config),
    .slave_id = sensor_config->slave_id,
    .start_register = sensor_config->register_address,
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
  if (!access_config()) {
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
