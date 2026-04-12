#include "carbon_dioxide.h"
#include "../config.h"

#include <Arduino.h>
#include <Wire.h>
#include <SensirionI2cScd30.h>
#include <SensirionI2cScd4x.h>

#ifndef CONFIG_CO2_SCD30_ADDR
#define CONFIG_CO2_SCD30_ADDR 0x61
#endif

#ifndef CONFIG_CO2_SCD4X_ADDR
#define CONFIG_CO2_SCD4X_ADDR 0x62
#endif

enum Co2Backend { CO2_NONE, CO2_SCD30, CO2_SCD4X };

static SensirionI2cScd30 scd30;
static SensirionI2cScd4x scd4x;
static Co2Backend backend = CO2_NONE;
static bool initialized = false;
static bool measuring = false;
#define CO2_MAX_PROBE_ATTEMPTS 3
static uint8_t probe_attempts = 0;

bool sensors::carbon_dioxide::initialize() noexcept {
  scd30.begin(Wire1, CONFIG_CO2_SCD30_ADDR);
  scd4x.begin(Wire1, CONFIG_CO2_SCD4X_ADDR);
  initialized = true;
  backend = CO2_NONE;

  uint8_t major, minor;
  if (scd30.readFirmwareVersion(major, minor) == 0) {
    scd30.softReset();
    delay(2000);
    if (scd30.startPeriodicMeasurement(0) == 0) {
      backend = CO2_SCD30;
      measuring = true;
      Serial.printf("[co2] SCD30 detected (fw %d.%d)\n", major, minor);
      return true;
    }
  }

  scd4x.wakeUp();
  scd4x.stopPeriodicMeasurement();
  delay(500);
  scd4x.reinit();
  delay(30);
  uint64_t serialNumber = 0;
  if (scd4x.getSerialNumber(serialNumber) == 0) {
    if (scd4x.startPeriodicMeasurement() == 0) {
      backend = CO2_SCD4X;
      measuring = true;
      Serial.printf("[co2] SCD4x detected (serial 0x%08lX%08lX)\n",
                    (uint32_t)(serialNumber >> 32), (uint32_t)(serialNumber & 0xFFFFFFFF));
      return true;
    }
  }

  Serial.println(F("[co2] no sensor found"));
  backend = CO2_NONE;
  return false;
}

bool sensors::carbon_dioxide::accessReading(CO2SensorData *sensor_data) noexcept {
  if (!sensor_data) return false;

  if (backend == CO2_NONE) {
    if (probe_attempts >= CO2_MAX_PROBE_ATTEMPTS) {
      sensor_data->ok = false;
      sensor_data->model = "none";
      return false;
    }
    probe_attempts++;
    if (!sensors::carbon_dioxide::initialize()) {
      sensor_data->ok = false;
      sensor_data->model = "none";
      return false;
    }
    probe_attempts = 0;
  }

  if (backend == CO2_SCD30) {
    sensor_data->model = "SCD30";
    uint16_t ready = 0;
    scd30.getDataReady(ready);
    if (!ready) { sensor_data->ok = false; return false; }

    float co2, temp, hum;
    if (scd30.readMeasurementData(co2, temp, hum) == 0) {
      sensor_data->co2_ppm = co2;
      sensor_data->temperature_celsius = temp;
      sensor_data->relative_humidity_percent = hum;
      sensor_data->ok = true;
      return true;
    }
    sensor_data->ok = false;
    return false;
  }

  if (backend == CO2_SCD4X) {
    sensor_data->model = "SCD4x";
    bool ready = false;
    scd4x.getDataReadyStatus(ready);
    if (!ready) { sensor_data->ok = false; return false; }

    uint16_t co2;
    float temp, hum;
    if (scd4x.readMeasurement(co2, temp, hum) == 0) {
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

bool sensors::carbon_dioxide::enable() noexcept {
  if (backend == CO2_SCD30) {
    if (scd30.startPeriodicMeasurement(0) == 0) { measuring = true; return true; }
  } else if (backend == CO2_SCD4X) {
    if (scd4x.startPeriodicMeasurement() == 0) { measuring = true; return true; }
  }
  return false;
}

bool sensors::carbon_dioxide::disable() noexcept {
  if (backend == CO2_SCD30) {
    if (scd30.stopPeriodicMeasurement() == 0) { measuring = false; return true; }
  } else if (backend == CO2_SCD4X) {
    if (scd4x.stopPeriodicMeasurement() == 0) { measuring = false; return true; }
  }
  return false;
}

bool sensors::carbon_dioxide::accessConfig(Co2Config *config) noexcept {
  if (!config) return false;

  config->measuring = measuring;
  config->measurement_interval_seconds = 0;
  config->auto_calibration_enabled = false;
  config->temperature_offset_celsius = 0.0f;
  config->altitude_meters = 0;

  if (backend == CO2_SCD30) {
    config->model = "SCD30";
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
    return true;
  }

  if (backend == CO2_SCD4X) {
    config->model = "SCD4x";
    config->measurement_interval_seconds = 5;
    return true;
  }

  config->model = "none";
  return false;
}

bool sensors::carbon_dioxide::configureInterval(uint16_t seconds) noexcept {
  if (backend == CO2_SCD30) return scd30.setMeasurementInterval(seconds) == 0;
  return false;
}

bool sensors::carbon_dioxide::configureAutoCalibration(bool enabled) noexcept {
  if (backend == CO2_SCD30) return scd30.activateAutoCalibration(enabled ? 1 : 0) == 0;
  return false;
}

bool sensors::carbon_dioxide::configureTemperatureOffset(float celsius) noexcept {
  if (backend == CO2_SCD30) return scd30.setTemperatureOffset((uint16_t)(celsius * 100)) == 0;
  return false;
}

bool sensors::carbon_dioxide::configureAltitude(uint16_t meters) noexcept {
  if (backend == CO2_SCD30) return scd30.setAltitudeCompensation(meters) == 0;
  return false;
}

bool sensors::carbon_dioxide::configureRecalibration(uint16_t co2_reference_ppm) noexcept {
  if (backend == CO2_SCD30) return scd30.forceRecalibration(co2_reference_ppm) == 0;
  return false;
}

bool sensors::carbon_dioxide::isAvailable() noexcept {
  return backend != CO2_NONE;
}

#ifdef PIO_UNIT_TESTING

#include "../testing/it.h"

static void co2_test_init(void) {
  TEST_MESSAGE("initializing CO2 module");
  Wire1.begin(config::i2c::BUS_1.sda_gpio, config::i2c::BUS_1.scl_gpio, config::i2c::FREQUENCY_KHZ * 1000);
  TEST_ASSERT_TRUE(sensors::carbon_dioxide::initialize());
  TEST_MESSAGE("CO2 module initialized");
}

static void co2_test_detect(void) {
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

static void co2_test_read(void) {
  if (!sensors::carbon_dioxide::isAvailable()) {
    TEST_IGNORE_MESSAGE("no CO2 sensor available");
    return;
  }
  delay(6000);
  CO2SensorData sensor_data = {};
  bool ok = sensors::carbon_dioxide::accessReading(&sensor_data);
  if (!ok) {
    TEST_IGNORE_MESSAGE("read not ready yet");
    return;
  }
  char msg[128];
  snprintf(msg, sizeof(msg), "%s: %.1f ppm, %.1f C, %.1f %%",
           sensor_data.model, sensor_data.co2_ppm, sensor_data.temperature_celsius,
           sensor_data.relative_humidity_percent);
  TEST_MESSAGE(msg);
  TEST_ASSERT_GREATER_THAN(0.0f, sensor_data.co2_ppm);
}

void sensors::carbon_dioxide::test() noexcept {
  it("user initializes the CO2 module", co2_test_init);
  it("user detects a CO2 sensor", co2_test_detect);
  it("user reads CO2 data", co2_test_read);
}

#endif
