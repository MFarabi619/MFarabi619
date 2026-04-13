// clang-format off
#ifndef CONFIG_H
#define CONFIG_H

#include <cstddef>
#include <cstdint>

// ─────────────────────────────────────────────────────────────────────────────
//  Build flags from platformio.ini (stay as #define — preprocessor injection)
// ─────────────────────────────────────────────────────────────────────────────

// CONFIG_WIFI_SSID  — from '-DCONFIG_WIFI_SSID="${sysenv.WIFI_SSID}"'
// CONFIG_WIFI_PASS  — from '-DCONFIG_WIFI_PASS="${sysenv.WIFI_PASSWORD}"'
// CONFIG_SSH_USER   — from '-DCONFIG_SSH_USER="root"' (optional override)

#ifndef CONFIG_WIFI_SSID
#define CONFIG_WIFI_SSID ""
#endif

#ifndef CONFIG_WIFI_PASS
#define CONFIG_WIFI_PASS ""
#endif

#ifndef CONFIG_SSH_USER
#define CONFIG_SSH_USER "root"
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  Typed configuration — mirrors firmware/src/config.rs
// ─────────────────────────────────────────────────────────────────────────────

namespace config {
  inline constexpr const char* HOSTNAME = "ceratina";
  inline constexpr const char* PLATFORM = "esp32s3";

  namespace led {
      inline constexpr uint8_t  GPIO       = 38;
      inline constexpr uint8_t  COUNT      = 1;
      inline constexpr uint8_t  BRIGHTNESS = 255;
  }

  namespace system {
      inline constexpr uint32_t TASK_STACK          = 8192;
      inline constexpr uint32_t SERIAL_BAUD         = 115200;
      inline constexpr uint16_t SHELL_SERVICE_MS    = 10;
  }

  namespace ssh {
      inline constexpr uint16_t    PORT            = 22;
      inline constexpr uint16_t    RING_SIZE       = 512;
      inline constexpr uint16_t    WRITE_BUF_SIZE  = 1024;
      inline constexpr uint32_t    TASK_STACK      = 32768;
      inline constexpr const char* HOSTKEY_PATH    = "/.ssh/id_ed25519";
  }

  namespace wifi {
      inline constexpr uint16_t CONNECT_TIMEOUT_MS = 15000;
      inline constexpr uint16_t POLL_MS            = 100;
      inline constexpr uint16_t STA_RETRY_MS       = 10000;
      inline constexpr const char* NVS_NAMESPACE   = "wifi";
      inline constexpr uint8_t  SSID_MAX_LEN       = 32;
      inline constexpr uint8_t  PASS_MAX_LEN       = 64;
      namespace ap {
          inline constexpr const char* SSID      = "ceratina-access-point";
          inline constexpr const char* PASSWORD  = "apidaesystems";
          inline constexpr uint8_t     CHANNEL   = 1;
      }
  }

  namespace telnet {
      inline constexpr bool     ENABLED      = true;
      inline constexpr uint16_t PORT         = 23;
      inline constexpr uint16_t RING_SIZE    = 512;
      inline constexpr uint16_t WRITE_BUF    = 1024;
      inline constexpr uint16_t KEEPALIVE_MS = 3000;
  }

  namespace ota {
      inline constexpr bool     ENABLED     = false;
      inline constexpr uint16_t PORT        = 3232;
      inline constexpr const char* PASSWORD = "";
      inline constexpr const char* SD_PATH  = "/update.bin";
  }

  namespace sntp {
      inline constexpr const char* SERVER_1        = "pool.ntp.org";
      inline constexpr const char* SERVER_2        = "time.nist.gov";
      inline constexpr const char* TIME_ZONE       = "EST5EDT,M3.2.0/2,M11.1.0/2";
      inline constexpr uint16_t    SYNC_TIMEOUT_MS = 10000;
  }

  namespace http {
      inline constexpr uint16_t PORT             = 80;
      inline constexpr bool     AUTH_ENABLED     = false;
      inline constexpr const char* AUTH_USER     = CONFIG_SSH_USER;
      inline constexpr const char* AUTH_PASSWORD = CONFIG_SSH_USER;
      inline constexpr const char* AUTH_REALM    = "ceratina";
  }

  namespace shell {
      inline constexpr uint16_t BUF_IN        = 256;
      inline constexpr uint16_t BUF_OUT       = 256;
      inline constexpr uint16_t MAX_PATH_LEN  = 128;
      inline constexpr uint16_t HOSTNAME_SIZE = 32;
  }

  namespace i2c {
      struct BusConfig { uint8_t sda_gpio; uint8_t scl_gpio; };

      inline constexpr BusConfig BUS_0            = {15, 16};
      inline constexpr BusConfig BUS_1            = {17, 18};
      inline constexpr uint32_t  FREQUENCY_KHZ    = 100;

      // Legacy board: a single relay on GPIO 5 powers all downstream I2C devices
      // when no mux is present.
      inline constexpr uint8_t   LEGACY_POWER_GPIO = 5;

      // New board: muxed sensor power is split across two rails.
      // The relationship is fixed by board wiring and is intentionally documented here
      // instead of hidden in arithmetic:
      //   mux channels 0, 2, 4, 6 -> GPIO 6
      //   mux channels 1, 3, 5, 7 -> GPIO 1
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

  namespace eeprom { // ──(AT24C32 on I2C bus 1)──
      inline constexpr uint8_t  I2C_ADDR   = 0x50;
      inline constexpr uint16_t PAGE_SIZE  = 32;
      inline constexpr uint16_t TOTAL_SIZE = 4096;
  }


  namespace temperature_humidity { // ──(CHT832X behind TCA9548A mux)──
      inline constexpr uint8_t  I2C_ADDR       = 0x44;
      inline constexpr uint8_t  MAX_SENSORS    = 8;
      inline constexpr uint16_t READ_DELAY_MS  = 100;
      inline constexpr uint8_t  SHT3X_RESET_GPIO_PIN = 4;
  }

  namespace wind {
      inline constexpr uint16_t SENSOR_DELAY_MS = 100;
  }

  namespace modbus {
      inline constexpr ModbusSensorConfig DEVICES[] = {
          {ModbusSensorKind::WindSpeed, 0, 20, 0},
          {ModbusSensorKind::WindDirection, 0, 30, 0},
      };

      inline constexpr size_t DEVICE_COUNT = sizeof(DEVICES) / sizeof(DEVICES[0]);
  }

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

    namespace voltage {// ──(ADS1115 on Wire1) ──
      inline constexpr uint8_t I2C_ADDR      = 0x48;
      inline constexpr uint8_t CHANNEL_COUNT = 4;
  }

  namespace scp {
      inline constexpr uint16_t BUF_SIZE = 4096;
  }

  namespace ws_shell {
      inline constexpr uint16_t RING_SIZE = 512;
      inline constexpr uint16_t WRITE_BUF = 1024;
  }

  namespace data_logger {
      inline constexpr const char *CSV_PATH = "/data.csv";
      inline constexpr uint32_t LOG_INTERVAL_MS = 5000;
  }

  namespace provisioning {
      inline constexpr bool        ENABLED       = false;
      inline constexpr const char* POP           = "ceratina";
      inline constexpr const char* SERVICE_UUID  = "ceaa0001-b5a3-f393-e0a9-e50e24dcca9e";
      inline constexpr const char* CONFIG_UUID   = "ceaa0002-b5a3-f393-e0a9-e50e24dcca9e";
      inline constexpr const char* NVS_NAMESPACE = "prov";
  }

  namespace buttons {
      inline constexpr int8_t   GPIO_1         = -1;  // BUG: Reserved for PSRAM SPI, fix in next board rev
      inline constexpr int8_t   GPIO_2         = 4;
      inline constexpr int8_t   GPIO_3         = 42;
      inline constexpr uint8_t  COUNT          = 3;
      inline constexpr uint16_t DEBOUNCE_MS    = 50;
      inline constexpr uint16_t LONG_PRESS_MS  = 1000;
  }

  namespace ble {
      inline constexpr bool     ENABLED     = false;
      inline constexpr uint32_t PASSKEY     = 123456;
      inline constexpr uint8_t  MAX_CLIENTS = 2;
      inline constexpr uint16_t RING_SIZE   = 512;
      inline constexpr uint16_t WRITE_BUF   = 512;
  }

  namespace smtp { // ──(Email)──
      // Edit these values directly.
      // Password is stored in NVS (key below).
      inline constexpr bool        ENABLED          = false;
      inline constexpr uint16_t    PORT             = 587;
      inline constexpr const char* HOST             = "";
      inline constexpr const char* DOMAIN           = "";
      inline constexpr const char* FROM_EMAIL       = "";
      inline constexpr const char* FROM_NAME        = "";
      inline constexpr const char* TO_EMAIL         = "";
      inline constexpr const char* LOGIN_EMAIL      = "";
      inline constexpr bool        AUTH_ENABLED     = false;
      inline constexpr bool        SSL_ENABLED      = false;
      inline constexpr bool        STARTTLS_ENABLED = false;
      inline constexpr bool        TEST_ENABLED     = false;
      inline constexpr const char* SUBJECT_PREFIX   = "[ceratina]";
      inline constexpr const char* NVS_KEY          = "SMTP_PASSWORD";
  }

  namespace cloudevents {
      inline constexpr const char* TENANT = "default-tenant";
      inline constexpr const char* SITE   = "default-site";
  }
} // namespace config

// ─────────────────────────────────────────────────────────────────────────────
//  Compile-time config validation
// ─────────────────────────────────────────────────────────────────────────────

static_assert(config::led::GPIO < 48, "Invalid neopixel GPIO");
static_assert(config::ssh::PORT > 0, "Invalid SSH port");
static_assert(config::http::PORT > 0, "Invalid HTTP port");
static_assert(config::telnet::PORT > 0, "Invalid telnet port");
static_assert(config::i2c::BUS_0.sda_gpio != config::i2c::BUS_0.scl_gpio,
              "I2C bus 0: SDA and SCL must differ");
static_assert(config::i2c::BUS_1.sda_gpio != config::i2c::BUS_1.scl_gpio,
              "I2C bus 1: SDA and SCL must differ");
static_assert(config::wifi::SSID_MAX_LEN == 32, "IEEE 802.11 SSID max is 32");
static_assert(config::wifi::PASS_MAX_LEN == 64, "IEEE 802.11 pass max is 64");
static_assert(config::shell::BUF_IN >= 64, "Shell input buffer too small");
static_assert(config::shell::BUF_OUT >= 64, "Shell output buffer too small");
static_assert(config::buttons::COUNT <= 8, "Too many buttons");

// ─────────────────────────────────────────────────────────────────────────────
//  Preprocessor guards (booleans can't be used in #if)
// ─────────────────────────────────────────────────────────────────────────────

#define CERATINA_TELNET_ENABLED     1
#define CERATINA_OTA_ENABLED        0
#define CERATINA_PROV_ENABLED       0
#define CERATINA_BLE_ENABLED        0
#define CERATINA_SMTP_ENABLED       0
#define CERATINA_SMTP_TEST_ENABLED  0
#define CERATINA_HTTP_AUTH_ENABLED  0

#endif // CONFIG_H
