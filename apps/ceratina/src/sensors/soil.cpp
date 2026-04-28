#include "soil.h"
#include "registry.h"

#include <config.h>
#include "../hardware/rs485.h"
#include "../networking/modbus.h"

#include <Arduino.h>
#include <string.h>

//--- helpers ----------------------------------------------------------------

static const config::SoilRegisterMap& register_map_for(config::SoilProbeTier tier) {
  return *config::soil::REGISTER_MAPS[static_cast<uint8_t>(tier)];
}

static const char* model_name_for(config::SoilProbeTier tier) {
  switch (tier) {
    case config::SoilProbeTier::MoistureTemperature:      return "SEN0600";
    case config::SoilProbeTier::MoistureTemperatureEC:     return "SEN0601";
    case config::SoilProbeTier::MoistureTemperatureECPH:   return "SEN0604";
    default:                                                return "Unknown";
  }
}

static void parse_soil_registers(const config::SoilRegisterMap &map,
                                 const uint16_t *words,
                                 SoilSensorData *data) {
  if (map.moisture_offset >= 0)
    data->moisture_percent = words[map.moisture_offset] / 10.0f;

  if (map.temperature_offset >= 0)
    data->temperature_celsius = static_cast<int16_t>(words[map.temperature_offset]) / 10.0f;

  if (map.conductivity_offset >= 0) {
    data->conductivity = words[map.conductivity_offset];
    data->has_conductivity = true;
  }

  if (map.ph_offset >= 0) {
    data->ph = words[map.ph_offset] / 10.0f;
    data->has_ph = true;
  }

  if (map.salinity_offset >= 0) {
    data->salinity = words[map.salinity_offset];
    data->has_salinity = true;
  }

  if (map.tds_offset >= 0) {
    data->tds = words[map.tds_offset];
    data->has_tds = true;
  }
}

//--- discovery --------------------------------------------------------------

static constexpr uint8_t MAX_PROBES = 8;

struct SoilProbeSlot {
  uint8_t slave_id;
  hardware::rs485::Channel channel;
  config::SoilProbeTier tier;
  bool responsive;
};

static SoilProbeSlot slots[MAX_PROBES] = {};
static uint8_t probe_count = 0;
static bool available = false;

struct SoilScanRange {
  hardware::rs485::Channel channel;
  uint8_t first_slave_id;
  uint8_t last_slave_id;
  config::SoilProbeTier tier;
};

static constexpr SoilScanRange SCAN_RANGES[] = {
  {hardware::rs485::Channel::Bus0, 100, 109, config::SoilProbeTier::MoistureTemperature},
  {hardware::rs485::Channel::Bus0, 110, 119, config::SoilProbeTier::MoistureTemperatureEC},
  {hardware::rs485::Channel::Bus0, 120, 129, config::SoilProbeTier::MoistureTemperatureECPH},
};

static void discover_probes() {
  probe_count = 0;
  memset(slots, 0, sizeof(slots));

  for (const auto &range : SCAN_RANGES) {
    ModbusScanResult results[10] = {};
    ModbusScanCommand scan = {
      .channel = range.channel,
      .first_slave_id = range.first_slave_id,
      .last_slave_id = range.last_slave_id,
      .results = results,
      .max_results = sizeof(results) / sizeof(results[0]),
      .result_count = 0,
    };

    networking::modbus::scan(&scan);

    for (size_t i = 0; i < scan.result_count; i++) {
      if (!results[i].responsive) continue;
      if (probe_count >= MAX_PROBES) return;

      slots[probe_count] = {
        .slave_id = results[i].slave_id,
        .channel = results[i].channel,
        .tier = range.tier,
        .responsive = true,
      };

      Serial.printf("[soil] probe slave %d responsive\n", results[i].slave_id);
      probe_count++;
    }
  }
}

//--- public API -------------------------------------------------------------

bool sensors::soil::access(uint8_t index, SoilSensorData *sensor_data) {
  if (!sensor_data) return false;
  memset(sensor_data, 0, sizeof(*sensor_data));
  sensor_data->ok = false;
  if (index >= probe_count) return false;

  const SoilProbeSlot &slot = slots[index];
  const auto &map = register_map_for(slot.tier);

  uint16_t output_words[9] = {};
  ReadHoldingRegistersCommand command = {
    .channel = slot.channel,
    .slave_id = slot.slave_id,
    .start_register = map.start_register,
    .register_count = map.register_count,
    .output_words = output_words,
    .error = ModbusError::NotInitialized,
  };

  if (!networking::modbus::readHoldingRegisters(&command)) return false;

  parse_soil_registers(map, output_words, sensor_data);
  sensor_data->slave_id = slot.slave_id;
  sensor_data->model = model_name_for(slot.tier);

  if (slot.tier != config::SoilProbeTier::MoistureTemperature) {
    uint16_t coefficient_words[3] = {};
    ReadHoldingRegistersCommand coefficient_command = {
      .channel = slot.channel,
      .slave_id = slot.slave_id,
      .start_register = 0x0022,
      .register_count = 3,
      .output_words = coefficient_words,
      .error = ModbusError::NotInitialized,
    };

    if (networking::modbus::readHoldingRegisters(&coefficient_command)) {
      sensor_data->conductivity_temperature_coefficient = coefficient_words[0] / 10.0f;
      sensor_data->salinity_coefficient = coefficient_words[1] / 100.0f;
      sensor_data->tds_coefficient = coefficient_words[2] / 100.0f;

      uint16_t calibration_words[3] = {};
      ReadHoldingRegistersCommand calibration_command = {
        .channel = slot.channel,
        .slave_id = slot.slave_id,
        .start_register = 0x0050,
        .register_count = 3,
        .output_words = calibration_words,
        .error = ModbusError::NotInitialized,
      };

      if (networking::modbus::readHoldingRegisters(&calibration_command)) {
        sensor_data->temperature_calibration = static_cast<int16_t>(calibration_words[0]) / 10.0f;
        sensor_data->moisture_calibration = static_cast<int16_t>(calibration_words[1]) / 10.0f;
        sensor_data->conductivity_calibration = calibration_words[2];
        sensor_data->has_calibration = true;
      }
    }
  }

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

#include <testing/utils.h>

static void test_soil_rejects_null(void) {
  WHEN("a null buffer is passed to access");
  THEN("it returns false");
  TEST_ASSERT_FALSE_MESSAGE(sensors::soil::access(0, nullptr),
      "device: access should fail with null pointer");
}

static void test_soil_rejects_out_of_range(void) {
  WHEN("an out-of-range probe index is requested");
  THEN("it returns false");
  SoilSensorData data = {};
  TEST_ASSERT_FALSE_MESSAGE(sensors::soil::access(255, &data),
      "device: access should fail for invalid index");
}

// --- register parsing tests ---

static void test_soil_parse_moisture_temperature(void) {
  WHEN("SEN0600 registers are parsed (moisture + temperature only)");
  uint16_t words[] = {658, 0xFF9B};
  SoilSensorData data = {};
  parse_soil_registers(config::soil::MOISTURE_TEMPERATURE, words, &data);

  TEST_ASSERT_FLOAT_WITHIN(0.01f, 65.8f, data.moisture_percent);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, -10.1f, data.temperature_celsius);
  TEST_ASSERT_FALSE(data.has_conductivity);
  TEST_ASSERT_FALSE(data.has_ph);
  TEST_ASSERT_FALSE(data.has_salinity);
  TEST_ASSERT_FALSE(data.has_tds);
}

static void test_soil_parse_moisture_temperature_ec(void) {
  WHEN("SEN0601 registers are parsed (moisture + temperature + EC)");
  uint16_t words[] = {450, 251, 1000, 500, 250};
  SoilSensorData data = {};
  parse_soil_registers(config::soil::MOISTURE_TEMPERATURE_EC, words, &data);

  TEST_ASSERT_FLOAT_WITHIN(0.01f, 45.0f, data.moisture_percent);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 25.1f, data.temperature_celsius);
  TEST_ASSERT_EQUAL_UINT16(1000, data.conductivity);
  TEST_ASSERT_TRUE(data.has_conductivity);
  TEST_ASSERT_EQUAL_UINT16(500, data.salinity);
  TEST_ASSERT_TRUE(data.has_salinity);
  TEST_ASSERT_EQUAL_UINT16(250, data.tds);
  TEST_ASSERT_TRUE(data.has_tds);
  TEST_ASSERT_FALSE(data.has_ph);
}

static void test_soil_parse_moisture_temperature_ec_ph(void) {
  WHEN("SEN0604 registers are parsed (moisture + temperature + EC + pH, gap at 4-6)");
  uint16_t words[] = {450, 251, 1000, 56, 0, 0, 0, 500, 250};
  SoilSensorData data = {};
  parse_soil_registers(config::soil::MOISTURE_TEMPERATURE_EC_PH, words, &data);

  TEST_ASSERT_FLOAT_WITHIN(0.01f, 45.0f, data.moisture_percent);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 25.1f, data.temperature_celsius);
  TEST_ASSERT_EQUAL_UINT16(1000, data.conductivity);
  TEST_ASSERT_TRUE(data.has_conductivity);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 5.6f, data.ph);
  TEST_ASSERT_TRUE(data.has_ph);
  TEST_ASSERT_EQUAL_UINT16(500, data.salinity);
  TEST_ASSERT_TRUE(data.has_salinity);
  TEST_ASSERT_EQUAL_UINT16(250, data.tds);
  TEST_ASSERT_TRUE(data.has_tds);
}

static void test_soil_negative_temperature(void) {
  WHEN("a negative temperature is parsed from two's complement");
  uint16_t words[] = {300, 0xFF9B};
  SoilSensorData data = {};
  parse_soil_registers(config::soil::MOISTURE_TEMPERATURE, words, &data);

  TEST_ASSERT_FLOAT_WITHIN(0.01f, -10.1f, data.temperature_celsius);
}

void sensors::soil::test() {
  MODULE("Soil");
  RUN_TEST(test_soil_rejects_null);
  RUN_TEST(test_soil_rejects_out_of_range);
  RUN_TEST(test_soil_parse_moisture_temperature);
  RUN_TEST(test_soil_parse_moisture_temperature_ec);
  RUN_TEST(test_soil_parse_moisture_temperature_ec_ph);
  RUN_TEST(test_soil_negative_temperature);
}

#endif
