#include "carbon_dioxide.h"
#include "registry.h"
#include <config.h>
#include <i2c.h>

#include <Arduino.h>
#include <SensirionI2cScd30.h>
#include <SensirionI2cScd4x.h>

enum Co2Backend { CO2_NONE, CO2_SCD30, CO2_SCD4X };

static SensirionI2cScd30 scd30;
static SensirionI2cScd4x scd4x;
static Co2Backend backend = CO2_NONE;
static bool measuring = false;

constexpr uint16_t SCD30_RESET_MS = 2000;
constexpr uint16_t SCD4X_STOP_MEASUREMENT_MS = 500;
constexpr uint8_t SCD4X_COMMAND_MS = 30;

static uint8_t resolved_bus = 0;
static int8_t resolved_mux_channel = config::i2c::DIRECT_CHANNEL;

// apply_selection / clearSelection must bracket every I2C op to a mux-behind
// sensor. They do more than route the TCA9548A: accessDevice also gates the
// channel's power rail via MUX_POWER_GPIO_ODD/EVEN (see hardware/i2c.cpp).
// Removing these calls silently cuts power mid-transaction on the next poll.
static void apply_selection(void) {
  if (resolved_mux_channel >= 0) {
    hardware::i2c::DeviceAccessCommand cmd = {};
    cmd.bus = resolved_bus == 0 ? hardware::i2c::Bus::Bus0 : hardware::i2c::Bus::Bus1;
    cmd.mux_channel = resolved_mux_channel;
    hardware::i2c::accessDevice(&cmd);
  }
}

static bool try_scd30_on(uint8_t bus, uint8_t address, int8_t mux_channel) {
  hardware::i2c::DeviceAccessCommand cmd = {};
  cmd.bus = bus == 0 ? hardware::i2c::Bus::Bus0 : hardware::i2c::Bus::Bus1;
  cmd.mux_channel = mux_channel;
  if (!hardware::i2c::accessDevice(&cmd)) return false;

  scd30.begin(*cmd.wire, address);
  uint8_t major, minor;
  if (scd30.readFirmwareVersion(major, minor) != 0) {
    hardware::i2c::clearSelection();
    return false;
  }
  scd30.softReset();
  delay(SCD30_RESET_MS);
  // SCD30 lacks a single-shot API. On power-gated boards clearSelection() cuts
  // the sensor rail, breaking periodic-measurement state persistence.
  if (scd30.startPeriodicMeasurement(0) != 0) {
    hardware::i2c::clearSelection();
    return false;
  }
  hardware::i2c::clearSelection();
  Serial.printf("[co2] SCD30 detected on bus %d (fw %d.%d)\n", bus, major, minor);
  return true;
}

static bool try_scd4x_on(uint8_t bus, uint8_t address, int8_t mux_channel) {
  hardware::i2c::DeviceAccessCommand cmd = {};
  cmd.bus = bus == 0 ? hardware::i2c::Bus::Bus0 : hardware::i2c::Bus::Bus1;
  cmd.mux_channel = mux_channel;
  if (!hardware::i2c::accessDevice(&cmd)) return false;

  scd4x.begin(*cmd.wire, address);
  scd4x.wakeUp();
  delay(SCD4X_COMMAND_MS);
  scd4x.stopPeriodicMeasurement();
  delay(SCD4X_STOP_MEASUREMENT_MS);
  scd4x.reinit();
  delay(SCD4X_COMMAND_MS);

  uint64_t serialNumber = 0;
  if (scd4x.getSerialNumber(serialNumber) != 0) {
    hardware::i2c::clearSelection();
    return false;
  }
  // Do NOT call startPeriodicMeasurement here. Board power gating cuts the
  // sensor rail at clearSelection() below, wiping any measurement state. SCD41
  // uses measureAndReadSingleShot() in access() instead.
  hardware::i2c::clearSelection();
  Serial.printf("[co2] SCD41 detected on bus %d (serial 0x%08lX%08lX)\n",
                bus, (uint32_t)(serialNumber >> 32), (uint32_t)(serialNumber & 0xFFFFFFFF));
  return true;
}

bool sensors::carbon_dioxide::initialize() {
  backend = CO2_NONE;
  resolved_mux_channel = config::i2c::DIRECT_CHANNEL;

  hardware::i2c::DiscoveredDevice dev = {};

  if (hardware::i2c::findDevice(0x61, &dev) && try_scd30_on(dev.bus, dev.address, dev.mux_channel)) {
    backend = CO2_SCD30;
    resolved_bus = dev.bus;
    resolved_mux_channel = dev.mux_channel;
    measuring = true;
  } else if (hardware::i2c::findDevice(0x62, &dev) && try_scd4x_on(dev.bus, dev.address, dev.mux_channel)) {
    backend = CO2_SCD4X;
    resolved_bus = dev.bus;
    resolved_mux_channel = dev.mux_channel;
    measuring = true;
  }

  if (backend == CO2_NONE) {
    Serial.println(F("[co2] no sensor found"));
    return false;
  }

  sensors::registry::add({
      .kind = SensorKind::CarbonDioxide,
      .name = "Carbon Dioxide",
      .isAvailable = sensors::carbon_dioxide::isAvailable,
      .instanceCount = []() -> uint8_t { return 1; },
      .poll = [](uint8_t, void *out, size_t cap) -> bool {
          if (cap < sizeof(CO2SensorData)) return false;
          return sensors::carbon_dioxide::access(static_cast<CO2SensorData *>(out));
      },
      .data_size = sizeof(CO2SensorData),
  });
  return true;
}

bool sensors::carbon_dioxide::access(CO2SensorData *sensor_data) {
  if (!sensor_data) return false;

  if (backend == CO2_SCD30) {
    sensor_data->model = "SCD30";
    apply_selection();
    uint16_t ready = 0;
    scd30.getDataReady(ready);
    if (!ready) {
      hardware::i2c::clearSelection();
      sensor_data->ok = false;
      return false;
    }

    float co2, temp, hum;
    if (scd30.readMeasurementData(co2, temp, hum) == 0) {
      hardware::i2c::clearSelection();
      sensor_data->co2_ppm = co2;
      sensor_data->temperature_celsius = temp;
      sensor_data->relative_humidity_percent = hum;
      sensor_data->ok = true;
      return true;
    }
    hardware::i2c::clearSelection();
    sensor_data->ok = false;
    return false;
  }

  if (backend == CO2_SCD4X) {
    // measureAndReadSingleShot blocks ~5s. This is a hardware constraint:
    // power is cut between polls, so we cannot split into fire-and-forget
    // + read-later — the sensor needs continuous power through the full
    // measurement window.
    sensor_data->model = "SCD41";
    apply_selection();
    uint16_t co2 = 0;
    float temp = 0.0f, hum = 0.0f;
    int16_t rc = scd4x.measureAndReadSingleShot(co2, temp, hum);
    hardware::i2c::clearSelection();
    if (rc == 0) {
      sensor_data->co2_ppm = (float)co2;
      sensor_data->temperature_celsius = temp;
      sensor_data->relative_humidity_percent = hum;
      sensor_data->ok = true;
      return true;
    }
    sensor_data->ok = false;
    return false;
  }

  sensor_data->ok = false;
  sensor_data->model = "none";
  return false;
}

bool sensors::carbon_dioxide::enable() {
  if (backend == CO2_NONE) return false;
  // SCD4X runs in single-shot mode (see access()), so there is no persistent
  // hardware state to start. `measuring` is pure UI-layer bookkeeping.
  if (backend == CO2_SCD4X) {
    measuring = true;
    return true;
  }
  apply_selection();
  bool ok = scd30.startPeriodicMeasurement(0) == 0;
  hardware::i2c::clearSelection();
  if (ok) measuring = true;
  return ok;
}

bool sensors::carbon_dioxide::disable() {
  if (backend == CO2_NONE) return false;
  // See enable(): SCD4X single-shot has no persistent state.
  if (backend == CO2_SCD4X) {
    measuring = false;
    return true;
  }
  apply_selection();
  bool ok = scd30.stopPeriodicMeasurement() == 0;
  hardware::i2c::clearSelection();
  if (ok) measuring = false;
  return ok;
}

bool sensors::carbon_dioxide::accessConfig(Co2Config *config) {
  if (!config) return false;

  config->measuring = measuring;
  config->measurement_interval_seconds = 0;
  config->auto_calibration_enabled = false;
  config->temperature_offset_celsius = 0.0f;
  config->altitude_meters = 0;

  if (backend == CO2_SCD30) {
    config->model = "SCD30";
    apply_selection();
    uint16_t interval;
    if (scd30.getMeasurementInterval(interval) == 0)
      config->measurement_interval_seconds = interval;
    uint16_t asc;
    if (scd30.getAutoCalibrationStatus(asc) == 0)
      config->auto_calibration_enabled = (asc != 0);
    uint16_t offset;
    if (scd30.getTemperatureOffset(offset) == 0)
      config->temperature_offset_celsius = offset / 100.0f;
    uint16_t alt;
    if (scd30.getAltitudeCompensation(alt) == 0)
      config->altitude_meters = alt;
    hardware::i2c::clearSelection();
    return true;
  }

  if (backend == CO2_SCD4X) {
    config->model = "SCD41";
    config->measurement_interval_seconds = 5;
    return true;
  }

  config->model = "none";
  return false;
}

bool sensors::carbon_dioxide::configureInterval(uint16_t seconds) {
  if (backend != CO2_SCD30) return false;
  apply_selection();
  bool ok = scd30.setMeasurementInterval(seconds) == 0;
  hardware::i2c::clearSelection();
  return ok;
}

bool sensors::carbon_dioxide::configureAutoCalibration(bool enabled) {
  if (backend != CO2_SCD30) return false;
  apply_selection();
  bool ok = scd30.activateAutoCalibration(enabled ? 1 : 0) == 0;
  hardware::i2c::clearSelection();
  return ok;
}

bool sensors::carbon_dioxide::configureTemperatureOffset(float celsius) {
  if (backend != CO2_SCD30) return false;
  apply_selection();
  bool ok = scd30.setTemperatureOffset((uint16_t)(celsius * 100)) == 0;
  hardware::i2c::clearSelection();
  return ok;
}

bool sensors::carbon_dioxide::configureAltitude(uint16_t meters) {
  if (backend != CO2_SCD30) return false;
  apply_selection();
  bool ok = scd30.setAltitudeCompensation(meters) == 0;
  hardware::i2c::clearSelection();
  return ok;
}

bool sensors::carbon_dioxide::configureRecalibration(uint16_t co2_reference_ppm) {
  if (backend != CO2_SCD30) return false;
  apply_selection();
  bool ok = scd30.forceRecalibration(co2_reference_ppm) == 0;
  hardware::i2c::clearSelection();
  return ok;
}

bool sensors::carbon_dioxide::isAvailable() {
  return backend != CO2_NONE;
}

#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

static void test_co2_init(void) {
  WHEN("the CO2 module is initialized");
  hardware::i2c::initialize();
  TEST_ASSERT_TRUE_MESSAGE(sensors::carbon_dioxide::initialize(),
    "device: CO2 module initialization failed");
}

static void test_co2_detect(void) {
  GIVEN("the CO2 module is initialized");
  THEN("a sensor backend is detected");
  if (!sensors::carbon_dioxide::isAvailable()) {
    TEST_IGNORE_MESSAGE("no CO2 sensor connected");
    return;
  }
  Co2Config config;
  sensors::carbon_dioxide::accessConfig(&config);
  char msg[64];
  snprintf(msg, sizeof(msg), "detected: %s", config.model);
  TEST_MESSAGE(msg);
}

static void test_co2_read(void) {
  GIVEN("a CO2 sensor is available");
  WHEN("a measurement is read");
  if (!sensors::carbon_dioxide::isAvailable()) {
    TEST_IGNORE_MESSAGE("no CO2 sensor available");
    return;
  }
  CO2SensorData sensor_data = {};
  bool ok = sensors::carbon_dioxide::access(&sensor_data);
  if (!ok) {
    TEST_IGNORE_MESSAGE("read not ready yet");
    return;
  }
  char msg[128];
  snprintf(msg, sizeof(msg), "%s: %.1f ppm, %.1f C, %.1f %%",
           sensor_data.model, sensor_data.co2_ppm, sensor_data.temperature_celsius,
           sensor_data.relative_humidity_percent);
  TEST_MESSAGE(msg);
  TEST_ASSERT_GREATER_THAN_FLOAT_MESSAGE(0.0f, sensor_data.co2_ppm,
    "device: CO2 reading must be > 0 ppm");
}

void sensors::carbon_dioxide::test() {
  RUN_TEST(test_co2_init);
  RUN_TEST(test_co2_detect);
  RUN_TEST(test_co2_read);
}

#endif
