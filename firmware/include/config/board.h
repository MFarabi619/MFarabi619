// clang-format off
#pragma once

#include <cstddef>
#include <cstdint>

namespace config {

  inline constexpr const char* PLATFORM = "esp32s3";

  namespace led {
      inline constexpr uint8_t  GPIO  = 38;
      inline constexpr uint8_t  COUNT = 1;
  }

  namespace system {
      inline constexpr uint32_t SERIAL_BAUD = 115200;
  }

  namespace i2c {
      struct BusConfig { uint8_t sda_gpio; uint8_t scl_gpio; };

      inline constexpr BusConfig BUS_0            = {15, 16};
      inline constexpr BusConfig BUS_1            = {17, 18};
      inline constexpr uint32_t  FREQUENCY_KHZ    = 100;

      inline constexpr uint8_t   LEGACY_POWER_GPIO   = 5;
      inline constexpr uint8_t   MUX_POWER_GPIO_ODD  = 1;
      inline constexpr uint8_t   MUX_POWER_GPIO_EVEN = 6;

      inline constexpr uint8_t   ADDR_MIN         = 1;
      inline constexpr uint8_t   ADDR_MAX         = 127;
      inline constexpr uint8_t   MUX_ADDR         = 0x70;
      inline constexpr int8_t    DIRECT_CHANNEL   = -1;
      inline constexpr int8_t    ANY_MUX_CHANNEL  = -2;
  }

  enum class I2CSensorKind : uint8_t {
      TemperatureHumidityCHT832X,
      TemperatureHumiditySHT3X,
      VoltageADS1115,
      CurrentINA228,
      CarbonDioxideSCD30,
      CarbonDioxideSCD4X,
      RTC_DS3231,
      EEPROM_AT24C32,
  };

  struct I2CSensorConfig {
      I2CSensorKind kind;
      uint8_t bus;
      uint8_t address;
      int8_t mux_channel;
  };

  namespace i2c_topology {
      inline constexpr I2CSensorConfig DEVICES[] = {
          {I2CSensorKind::RTC_DS3231,                 0, 0x68, i2c::DIRECT_CHANNEL},
          {I2CSensorKind::EEPROM_AT24C32,             1, 0x50, i2c::DIRECT_CHANNEL},
          {I2CSensorKind::VoltageADS1115,             1, 0x48, i2c::ANY_MUX_CHANNEL},
          {I2CSensorKind::CarbonDioxideSCD30,         1, 0x61, i2c::DIRECT_CHANNEL},
          {I2CSensorKind::CarbonDioxideSCD4X,         1, 0x62, i2c::DIRECT_CHANNEL},
          {I2CSensorKind::TemperatureHumidityCHT832X, 1, 0x44, i2c::ANY_MUX_CHANNEL},
          {I2CSensorKind::TemperatureHumiditySHT3X,   0, 0x44, i2c::DIRECT_CHANNEL},
          {I2CSensorKind::TemperatureHumiditySHT3X,   1, 0x44, i2c::DIRECT_CHANNEL},
      };

      inline constexpr size_t DEVICE_COUNT = sizeof(DEVICES) / sizeof(DEVICES[0]);
  }

  namespace rs485 {
      inline constexpr uint8_t CHANNEL_COUNT = 2;

      struct BusConfig {
          int8_t tx_gpio;
          int8_t rx_gpio;
          int8_t de_re_gpio;
          uint32_t baud_rate;
      };

      inline constexpr BusConfig BUS_0 = {45, 48, 47, 9600};
      inline constexpr BusConfig BUS_1 = {40, 39, 41, 4800};
  }

  enum class ModbusSensorKind : uint8_t {
      WindSpeed,
      WindDirection,
      SolarRadiation,
      SoilProbe,
  };

  struct ModbusSensorConfig {
      ModbusSensorKind kind;
      uint8_t channel;
      uint8_t slave_id;
      uint16_t register_address;
  };

  namespace modbus {
      inline constexpr ModbusSensorConfig DEVICES[] = {
          {ModbusSensorKind::WindSpeed, 0, 20, 0},
          {ModbusSensorKind::WindDirection, 0, 30, 0},
      };

      inline constexpr size_t DEVICE_COUNT = sizeof(DEVICES) / sizeof(DEVICES[0]);
  }

  namespace eeprom {
      inline constexpr uint8_t  I2C_ADDR   = 0x50;
      inline constexpr uint16_t PAGE_SIZE  = 32;
      inline constexpr uint16_t TOTAL_SIZE = 4096;
  }

  namespace temperature_humidity {
      inline constexpr uint8_t  I2C_ADDR             = 0x44;
      inline constexpr uint8_t  SHT3X_RESET_GPIO_PIN = 4;
  }

  namespace voltage {
      inline constexpr uint8_t I2C_ADDR = 0x48;
  }

  namespace current {
      inline constexpr uint8_t  I2C_ADDR              = 0x40;
      inline constexpr float    SHUNT_RESISTANCE_OHMS  = 0.015f;
      inline constexpr float    MAX_EXPECTED_CURRENT_A = 10.0f;
  }

  namespace buttons {
      inline constexpr int8_t  GPIO_1 = -1;
      inline constexpr int8_t  GPIO_2 = 4;
      inline constexpr int8_t  GPIO_3 = 42;
      inline constexpr uint8_t COUNT  = 3;
  }

} // namespace config
