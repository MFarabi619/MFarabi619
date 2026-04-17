#include "current.h"
#include "registry.h"

#include <config.h>
#include <i2c.h>

#include <Arduino.h>
#include <Adafruit_INA228.h>

namespace {

Adafruit_INA228 ina228;
bool ready = false;

config::I2CSensorConfig resolved_config = {};
int8_t resolved_mux_channel = config::i2c::DIRECT_CHANNEL;

bool probe_device(const config::I2CSensorConfig &sensor_config, int8_t mux_channel) {
  hardware::i2c::DeviceAccessCommand command = {
    .bus = sensor_config.bus == 0 ? hardware::i2c::Bus::Bus0 : hardware::i2c::Bus::Bus1,
    .mux_channel = mux_channel,
    .wire = nullptr,
    .ok = false,
  };
  if (!hardware::i2c::accessDevice(&command)) return false;

  bool ok = ina228.begin(sensor_config.address, command.wire);
  hardware::i2c::clearSelection();
  return ok;
}

void apply_selection(void) {
  if (resolved_mux_channel >= 0) {
    hardware::i2c::DeviceAccessCommand command = {
      .bus = resolved_config.bus == 0 ? hardware::i2c::Bus::Bus0 : hardware::i2c::Bus::Bus1,
      .mux_channel = resolved_mux_channel,
      .wire = nullptr,
      .ok = false,
    };
    hardware::i2c::accessDevice(&command);
  }
}

}

bool sensors::current::initialize() {
  ready = false;
  resolved_mux_channel = config::i2c::DIRECT_CHANNEL;

  config::I2CSensorConfig sensor_config = {};
  bool found = false;
  for (size_t index = 0; index < config::i2c_topology::DEVICE_COUNT; index++) {
    const config::I2CSensorConfig &candidate = config::i2c_topology::DEVICES[index];
    if (candidate.kind == config::I2CSensorKind::CurrentINA228) {
      sensor_config = candidate;
      found = true;
      break;
    }
  }
  if (!found) return false;

  hardware::i2c::TopologySnapshot topology = {};
  hardware::i2c::accessTopology(&topology);

  if (sensor_config.mux_channel == config::i2c::DIRECT_CHANNEL) {
    ready = probe_device(sensor_config, config::i2c::DIRECT_CHANNEL);
  } else if (sensor_config.mux_channel == config::i2c::ANY_MUX_CHANNEL) {
    if (topology.mux_present && sensor_config.bus == 1) {
      uint8_t channel_mask = hardware::i2c::mux.find(sensor_config.address);
      if (channel_mask != 0) {
        for (uint8_t channel = 0; channel < hardware::i2c::mux.channelCount(); channel++) {
          if (channel_mask & (1 << channel)) {
            resolved_mux_channel = (int8_t)channel;
            ready = probe_device(sensor_config, resolved_mux_channel);
            if (ready) break;
          }
        }
      }
    }
  } else {
    if (topology.mux_present && sensor_config.bus == 1) {
      resolved_mux_channel = sensor_config.mux_channel;
      ready = probe_device(sensor_config, resolved_mux_channel);
    }
  }

  if (ready) {
    resolved_config = sensor_config;
    ina228.setShunt(config::current::SHUNT_RESISTANCE_OHMS,
                    config::current::MAX_EXPECTED_CURRENT_A);
    Serial.printf("[current] INA228 at 0x%02X on bus %d\n",
                  sensor_config.address, sensor_config.bus);

    sensors::registry::add({
        .kind = SensorKind::Current,
        .name = "Current",
        .isAvailable = sensors::current::isAvailable,
        .instanceCount = []() -> uint8_t { return 1; },
        .poll = [](uint8_t, void *out, size_t cap) -> bool {
            if (cap < sizeof(CurrentSensorData)) return false;
            return sensors::current::access(static_cast<CurrentSensorData *>(out));
        },
        .data_size = sizeof(CurrentSensorData),
    });
  }

  hardware::i2c::clearSelection();
  return ready;
}

bool sensors::current::isAvailable() {
  return ready;
}

bool sensors::current::access(CurrentSensorData *sensor_data) {
  if (!ready) return false;
  if (!sensor_data) return false;

  apply_selection();

  sensor_data->current_mA = ina228.readCurrent() * 1000.0f;
  sensor_data->bus_voltage_V = ina228.readBusVoltage();
  sensor_data->shunt_voltage_mV = ina228.readShuntVoltage() * 1000.0f;
  sensor_data->power_mW = ina228.readPower() * 1000.0f;
  sensor_data->energy_J = ina228.readEnergy();
  sensor_data->charge_C = ina228.readCharge();
  sensor_data->die_temperature_C = ina228.readDieTemp();
  sensor_data->ok = true;

  hardware::i2c::clearSelection();
  return true;
}

#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>


static void test_current_initializes(void) {
  WHEN("the INA228 current monitor is initialized");
  test_ensure_wire1_with_power();
  hardware::i2c::initialize();

  if (!sensors::current::initialize()) {
    TEST_IGNORE_MESSAGE("current::initialize() failed — skipping");
    return;
  }

}

static void test_current_reads(void) {
  GIVEN("the INA228 is available");
  WHEN("current monitor values are read");

  if (!sensors::current::isAvailable()) {
    TEST_IGNORE_MESSAGE("INA228 not available — skipping");
    return;
  }

  CurrentSensorData data = {};
  bool ok = sensors::current::access(&data);
  TEST_ASSERT_TRUE_MESSAGE(ok, "device: current::access() failed");

  char msg[128];
  snprintf(msg, sizeof(msg), "I=%.2fmA V=%.3fV P=%.2fmW T=%.1fC",
           data.current_mA, data.bus_voltage_V, data.power_mW, data.die_temperature_C);
  TEST_MESSAGE(msg);
}

static void test_current_rejects_null(void) {
  WHEN("a null buffer is passed to access");
  THEN("it returns false");
  TEST_ASSERT_FALSE_MESSAGE(sensors::current::access(nullptr),
      "device: access should fail with null pointer");
}

void sensors::current::test() {
  MODULE("Current");
  RUN_TEST(test_current_initializes);
  RUN_TEST(test_current_reads);
  RUN_TEST(test_current_rejects_null);
}

#endif
