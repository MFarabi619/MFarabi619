#include "carbon_dioxide.h"
#include "../config.h"
#include "../hardware/i2c.h"

#include <Arduino.h>
#include <SensirionI2cScd30.h>
#include <SensirionI2cScd4x.h>

enum Co2Backend { CO2_NONE, CO2_SCD30, CO2_SCD4X };

static SensirionI2cScd30 scd30;
static SensirionI2cScd4x scd4x;
static Co2Backend backend = CO2_NONE;
static bool initialized = false;
static bool measuring = false;
#define CO2_MAX_PROBE_ATTEMPTS 3
static uint8_t probe_attempts = 0;
static config::I2CSensorConfig scd30_config = {config::I2CSensorKind::CarbonDioxideSCD30, 1, 0x61, config::i2c::DIRECT_CHANNEL};
static config::I2CSensorConfig scd4x_config = {config::I2CSensorKind::CarbonDioxideSCD4X, 1, 0x62, config::i2c::DIRECT_CHANNEL};

namespace {

bool load_configs(void) {
  bool found_scd30 = false;
  bool found_scd4x = false;

  for (size_t index = 0; index < config::i2c_topology::DEVICE_COUNT; index++) {
    const config::I2CSensorConfig &sensor_config = config::i2c_topology::DEVICES[index];
    if (sensor_config.kind == config::I2CSensorKind::CarbonDioxideSCD30) {
      scd30_config = sensor_config;
      found_scd30 = true;
    } else if (sensor_config.kind == config::I2CSensorKind::CarbonDioxideSCD4X) {
      scd4x_config = sensor_config;
      found_scd4x = true;
    }
  }

  return found_scd30 || found_scd4x;
}

bool access_i2c_device(const config::I2CSensorConfig &sensor_config,
                       hardware::i2c::DeviceAccessCommand *command) {
  if (!command) return false;
  command->bus = sensor_config.bus == 0 ? hardware::i2c::Bus::Bus0 : hardware::i2c::Bus::Bus1;
  command->mux_channel = sensor_config.mux_channel;
  command->wire = nullptr;
  command->ok = false;
  return hardware::i2c::accessDevice(command);
}

}

bool sensors::carbon_dioxide::initialize() {
  if (!load_configs()) {
    backend = CO2_NONE;
    return false;
  }

  initialized = true;
  backend = CO2_NONE;

  hardware::i2c::DeviceAccessCommand scd30_device = {};
  if (access_i2c_device(scd30_config, &scd30_device)) {
    scd30.begin(*scd30_device.wire, scd30_config.address);

    uint8_t major, minor;
    if (scd30.readFirmwareVersion(major, minor) == 0) {
      scd30.softReset();
      delay(2000);
      if (scd30.startPeriodicMeasurement(0) == 0) {
        backend = CO2_SCD30;
        measuring = true;
        hardware::i2c::clearSelection();
        Serial.printf("[co2] SCD30 detected (fw %d.%d)\n", major, minor);
        return true;
      }
    }
    hardware::i2c::clearSelection();
  }

  hardware::i2c::DeviceAccessCommand scd4x_device = {};
  if (access_i2c_device(scd4x_config, &scd4x_device)) {
    scd4x.begin(*scd4x_device.wire, scd4x_config.address);

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
        hardware::i2c::clearSelection();
        Serial.printf("[co2] SCD4x detected (serial 0x%08lX%08lX)\n",
                      (uint32_t)(serialNumber >> 32), (uint32_t)(serialNumber & 0xFFFFFFFF));
        return true;
      }
    }
    hardware::i2c::clearSelection();
  }

  if (probe_attempts == 0) {
    Serial.println(F("[co2] no sensor found"));
  }
  backend = CO2_NONE;
  return false;
}

bool sensors::carbon_dioxide::accessReading(CO2SensorData *sensor_data) {
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

bool sensors::carbon_dioxide::enable() {
  if (backend == CO2_SCD30) {
    if (scd30.startPeriodicMeasurement(0) == 0) { measuring = true; return true; }
  } else if (backend == CO2_SCD4X) {
    if (scd4x.startPeriodicMeasurement() == 0) { measuring = true; return true; }
  }
  return false;
}

bool sensors::carbon_dioxide::disable() {
  if (backend == CO2_SCD30) {
    if (scd30.stopPeriodicMeasurement() == 0) { measuring = false; return true; }
  } else if (backend == CO2_SCD4X) {
    if (scd4x.stopPeriodicMeasurement() == 0) { measuring = false; return true; }
  }
  return false;
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

bool sensors::carbon_dioxide::configureInterval(uint16_t seconds) {
  if (backend == CO2_SCD30) return scd30.setMeasurementInterval(seconds) == 0;
  return false;
}

bool sensors::carbon_dioxide::configureAutoCalibration(bool enabled) {
  if (backend == CO2_SCD30) return scd30.activateAutoCalibration(enabled ? 1 : 0) == 0;
  return false;
}

bool sensors::carbon_dioxide::configureTemperatureOffset(float celsius) {
  if (backend == CO2_SCD30) return scd30.setTemperatureOffset((uint16_t)(celsius * 100)) == 0;
  return false;
}

bool sensors::carbon_dioxide::configureAltitude(uint16_t meters) {
  if (backend == CO2_SCD30) return scd30.setAltitudeCompensation(meters) == 0;
  return false;
}

bool sensors::carbon_dioxide::configureRecalibration(uint16_t co2_reference_ppm) {
  if (backend == CO2_SCD30) return scd30.forceRecalibration(co2_reference_ppm) == 0;
  return false;
}

bool sensors::carbon_dioxide::isAvailable() {
  return backend != CO2_NONE;
}

#ifdef PIO_UNIT_TESTING

#include "../testing/it.h"

static void co2_test_init(void) {
  TEST_MESSAGE("initializing CO2 module");
  hardware::i2c::initialize();
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

void sensors::carbon_dioxide::test() {
  it("user initializes the CO2 module", co2_test_init);
  it("user detects a CO2 sensor", co2_test_detect);
  it("user reads CO2 data", co2_test_read);
}

#endif
