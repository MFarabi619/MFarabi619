#include "current.h"
#include "registry.h"

#include <config.h>
#include <i2c.h>

#include <Arduino.h>
#include <Adafruit_INA228.h>

namespace {

Adafruit_INA228 ina228;
bool ready = false;

uint8_t resolved_bus = 0;
int8_t resolved_mux_channel = config::i2c::DIRECT_CHANNEL;

void apply_selection(void) {
  if (resolved_mux_channel >= 0) {
    hardware::i2c::DeviceAccessCommand command = {
      .bus = resolved_bus == 0 ? hardware::i2c::Bus::Bus0 : hardware::i2c::Bus::Bus1,
      .mux_channel = resolved_mux_channel,
      .wire = nullptr,
      .ok = false,
    };
    hardware::i2c::accessDevice(&command);
  }
}

bool probe_ina228_discovered(const hardware::i2c::DiscoveredDevice &dev) {
  hardware::i2c::DeviceAccessCommand command = {
    .bus = dev.bus == 0 ? hardware::i2c::Bus::Bus0 : hardware::i2c::Bus::Bus1,
    .mux_channel = dev.mux_channel,
    .wire = nullptr,
    .ok = false,
  };
  if (!hardware::i2c::accessDevice(&command)) return false;

  bool ok = ina228.begin(dev.address, command.wire);
  hardware::i2c::clearSelection();
  if (!ok) return false;

  resolved_bus = dev.bus;
  resolved_mux_channel = dev.mux_channel;
  ready = true;

  ina228.setShunt(config::current::SHUNT_RESISTANCE_OHMS,
                  config::current::MAX_EXPECTED_CURRENT_A);
  Serial.printf("[current] INA228 at 0x%02X on bus %d\n", dev.address, dev.bus);

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
  return true;
}

}

void sensors::current::registerProbes() {
  ready = false;
  resolved_mux_channel = config::i2c::DIRECT_CHANNEL;
  hardware::i2c::registerProbe({0x40, probe_ina228_discovered, "INA228", 10});
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

  sensors::current::registerProbes();
  hardware::i2c::runDiscovery();
  hardware::i2c::probeAll();
  if (!sensors::current::isAvailable()) {
    TEST_IGNORE_MESSAGE("INA228 not found — skipping");
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
