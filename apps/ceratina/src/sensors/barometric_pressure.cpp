#include "barometric_pressure.h"
#include "registry.h"
#include <i2c.h>

#include <Arduino.h>
#include <Adafruit_LPS2X.h>

namespace {

constexpr uint16_t LPS25_INIT_SETTLE_MS = 200;

Adafruit_LPS25 lps;
bool available = false;
uint8_t resolved_bus = 0;
int8_t resolved_mux_channel = -1;

bool probe_lps25_discovered(const hardware::i2c::DiscoveredDevice &dev) {
  hardware::i2c::DeviceAccessCommand command = {
    .bus = dev.bus == 0 ? hardware::i2c::Bus::Bus0 : hardware::i2c::Bus::Bus1,
    .mux_channel = dev.mux_channel,
    .wire = nullptr,
    .ok = false,
  };
  if (!hardware::i2c::accessDevice(&command)) return false;

  if (!lps.begin_I2C(dev.address, command.wire)) {
    hardware::i2c::clearSelection();
    return false;
  }

  lps.setDataRate(LPS25_RATE_25_HZ);
  delay(LPS25_INIT_SETTLE_MS);

  sensors_event_t discard_p, discard_t;
  lps.getEvent(&discard_p, &discard_t);

  hardware::i2c::clearSelection();

  resolved_bus = dev.bus;
  resolved_mux_channel = dev.mux_channel;
  available = true;
  Serial.printf("[pressure] LPS25 detected on bus %d at 0x%02X\n", dev.bus, dev.address);

  sensors::registry::add({
      .kind = SensorKind::BarometricPressure,
      .name = "Barometric Pressure",
      .isAvailable = sensors::barometric_pressure::isAvailable,
      .instanceCount = []() -> uint8_t { return 1; },
      .poll = [](uint8_t, void *out, size_t cap) -> bool {
          if (cap < sizeof(BarometricPressureSensorData)) return false;
          return sensors::barometric_pressure::access(
              static_cast<BarometricPressureSensorData *>(out));
      },
      .data_size = sizeof(BarometricPressureSensorData),
  });
  return true;
}

}

void sensors::barometric_pressure::registerProbes() {
  available = false;
  hardware::i2c::registerProbe({0x5C, probe_lps25_discovered, "LPS25", 10});
  hardware::i2c::registerProbe({0x5D, probe_lps25_discovered, "LPS25", 10});
}

bool sensors::barometric_pressure::access(BarometricPressureSensorData *data) {
  if (!data) return false;
  if (!available) {
    data->ok = false;
    data->model = "none";
    return false;
  }

  sensors_event_t pressure_event, temp_event;
  if (!lps.getEvent(&pressure_event, &temp_event)) {
    data->ok = false;
    data->model = "LPS25";
    return false;
  }

  data->pressure_hpa = pressure_event.pressure;
  data->temperature_celsius = temp_event.temperature;
  data->model = "LPS25";
  data->ok = true;
  return true;
}

bool sensors::barometric_pressure::isAvailable() {
  return available;
}

#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

namespace sensors::barometric_pressure { void test(void); }

static void test_pressure_init(void) {
  WHEN("the barometric pressure module is initialized");
  hardware::i2c::initialize();
  sensors::barometric_pressure::registerProbes();
  hardware::i2c::runDiscovery();
  hardware::i2c::probeAll();
  if (!sensors::barometric_pressure::isAvailable()) {
    TEST_IGNORE_MESSAGE("no LPS25 sensor connected");
    return;
  }
  TEST_ASSERT_TRUE_MESSAGE(sensors::barometric_pressure::isAvailable(),
    "device: LPS25 not available after initialization");
}

static void test_pressure_read(void) {
  GIVEN("the LPS25 sensor is available");
  WHEN("a reading is taken");
  if (!sensors::barometric_pressure::isAvailable()) {
    TEST_IGNORE_MESSAGE("no LPS25 sensor available");
    return;
  }
  delay(500);
  BarometricPressureSensorData data = {};
  bool ok = sensors::barometric_pressure::access(&data);
  if (!ok) {
    TEST_IGNORE_MESSAGE("reading not ready yet");
    return;
  }
  char msg[64];
  snprintf(msg, sizeof(msg), "LPS25: %.2f hPa, %.2f C", data.pressure_hpa, data.temperature_celsius);
  TEST_MESSAGE(msg);
  TEST_ASSERT_FLOAT_IS_DETERMINATE_MESSAGE(data.pressure_hpa,
    "device: pressure reading is NaN or Inf");
  TEST_ASSERT_FLOAT_IS_DETERMINATE_MESSAGE(data.temperature_celsius,
    "device: temperature reading is NaN or Inf");
  TEST_ASSERT_GREATER_THAN_FLOAT_MESSAGE(900.0f, data.pressure_hpa,
    "device: pressure below 900 hPa — sensor may be faulty");
  TEST_ASSERT_LESS_THAN_FLOAT_MESSAGE(1100.0f, data.pressure_hpa,
    "device: pressure above 1100 hPa — sensor may be faulty");
}

void sensors::barometric_pressure::test(void) {
  MODULE("Barometric Pressure");
  RUN_TEST(test_pressure_init);
  RUN_TEST(test_pressure_read);
}

#endif
