#include "soil.h"
#include "registry.h"

#include "../config.h"
#include "../hardware/rs485.h"
#include "../networking/modbus.h"

#include <Arduino.h>
#include <string.h>

namespace {

struct SoilProbeSlot {
  uint8_t slave_id;
  hardware::rs485::Channel channel;
  bool responsive;
};

SoilProbeSlot slots[8] = {};
uint8_t probe_count = 0;
bool available = false;

void discover_probes() {
  probe_count = 0;
  memset(slots, 0, sizeof(slots));

  for (size_t index = 0; index < config::modbus::DEVICE_COUNT; index++) {
    const config::ModbusSensorConfig &sensor_config = config::modbus::DEVICES[index];
    if (sensor_config.kind != config::ModbusSensorKind::SoilProbe) continue;
    if (probe_count >= sizeof(slots) / sizeof(slots[0])) break;

    hardware::rs485::Channel channel = sensor_config.channel == 0
        ? hardware::rs485::Channel::Bus0
        : hardware::rs485::Channel::Bus1;

    uint16_t output_words[5] = {};
    ReadHoldingRegistersCommand command = {
      .channel = channel,
      .slave_id = sensor_config.slave_id,
      .start_register = sensor_config.register_address,
      .register_count = 5,
      .output_words = output_words,
      .error = ModbusError::NotInitialized,
    };

    bool ok = networking::modbus::readHoldingRegisters(&command);
    slots[probe_count] = {
      .slave_id = sensor_config.slave_id,
      .channel = channel,
      .responsive = ok,
    };

    if (ok) {
      Serial.printf("[soil] probe slave %d responsive\n", sensor_config.slave_id);
    }
    probe_count++;
  }
}

}

bool sensors::soil::access(uint8_t index, SoilSensorData *sensor_data) {
  if (!sensor_data) return false;
  memset(sensor_data, 0, sizeof(*sensor_data));
  sensor_data->ok = false;
  if (index >= probe_count) return false;

  const SoilProbeSlot &slot = slots[index];

  const config::ModbusSensorConfig *sensor_config = nullptr;
  for (size_t i = 0; i < config::modbus::DEVICE_COUNT; i++) {
    if (config::modbus::DEVICES[i].kind == config::ModbusSensorKind::SoilProbe &&
        config::modbus::DEVICES[i].slave_id == slot.slave_id) {
      sensor_config = &config::modbus::DEVICES[i];
      break;
    }
  }
  if (!sensor_config) return false;

  uint16_t output_words[5] = {};
  ReadHoldingRegistersCommand command = {
    .channel = slot.channel,
    .slave_id = slot.slave_id,
    .start_register = sensor_config->register_address,
    .register_count = 5,
    .output_words = output_words,
    .error = ModbusError::NotInitialized,
  };

  if (!networking::modbus::readHoldingRegisters(&command)) return false;

  sensor_data->moisture_percent = output_words[0] / 10.0f;
  sensor_data->temperature_celsius = static_cast<int16_t>(output_words[1]) / 10.0f;
  sensor_data->conductivity = output_words[2];
  sensor_data->salinity = output_words[3];
  sensor_data->tds = output_words[4];
  sensor_data->slave_id = slot.slave_id;
  sensor_data->ok = true;
  return true;
}

bool sensors::soil::initialize() {
  discover_probes();
  available = false;
  for (uint8_t i = 0; i < probe_count; i++) {
    if (slots[i].responsive) {
      available = true;
      break;
    }
  }
  if (available) {
    sensors::registry::add({
        .kind = SensorKind::Soil,
        .name = "Soil",
        .isAvailable = sensors::soil::isAvailable,
        .instanceCount = sensors::soil::probeCount,
        .poll = [](uint8_t index, void *out, size_t cap) -> bool {
            if (cap < sizeof(SoilSensorData)) return false;
            return sensors::soil::access(
                index, static_cast<SoilSensorData *>(out));
        },
        .data_size = sizeof(SoilSensorData),
    });
  }
  return available;
}

bool sensors::soil::isAvailable() {
  return available;
}

uint8_t sensors::soil::probeCount() {
  return probe_count;
}

#ifdef PIO_UNIT_TESTING

#include "../testing/it.h"

static void soil_test_config_lookup(void) {
  TEST_MESSAGE("user checks if soil probes are in the modbus topology");

  uint8_t count = 0;
  for (size_t i = 0; i < config::modbus::DEVICE_COUNT; i++) {
    if (config::modbus::DEVICES[i].kind == config::ModbusSensorKind::SoilProbe)
      count++;
  }

  if (count == 0) {
    TEST_IGNORE_MESSAGE("no soil probes configured — skipping");
    return;
  }

  char msg[32];
  snprintf(msg, sizeof(msg), "%d soil probe(s) in topology", count);
  TEST_MESSAGE(msg);
}

static void soil_test_rejects_null(void) {
  TEST_MESSAGE("user passes null buffer to access");
  TEST_ASSERT_FALSE_MESSAGE(sensors::soil::access(0, nullptr),
      "device: access should fail with null pointer");
}

static void soil_test_rejects_out_of_range(void) {
  TEST_MESSAGE("user requests probe index beyond count");
  SoilSensorData data = {};
  TEST_ASSERT_FALSE_MESSAGE(sensors::soil::access(255, &data),
      "device: access should fail for invalid index");
}

void sensors::soil::test() {
  it("user checks soil probe config lookup", soil_test_config_lookup);
  it("user observes that null buffer is rejected", soil_test_rejects_null);
  it("user observes that out-of-range index is rejected", soil_test_rejects_out_of_range);
}

#endif
