// clang-format off
#pragma once

#include "features.h"

#include <cstddef>
#include <cstdint>

namespace config {

  inline constexpr const char* HOSTNAME = "ceratina";

  namespace led {
      inline constexpr uint8_t  BRIGHTNESS = 255;
      inline constexpr uint8_t  FRAME_MS   = 20;
  }

  namespace system {
      inline constexpr uint32_t TASK_STACK          = 8192;
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
      inline constexpr uint16_t PORT         = 23;
      inline constexpr uint16_t RING_SIZE    = 512;
      inline constexpr uint16_t WRITE_BUF    = 1024;
      inline constexpr uint16_t KEEPALIVE_MS = 3000;
  }

  namespace ota {
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
      inline constexpr uint16_t POWER_SETTLE_MS     = 100;
      inline constexpr uint16_t DISCOVERY_SETTLE_MS  = 500;
  }

  namespace temperature_humidity {
      inline constexpr uint8_t  MAX_SENSORS    = 8;
      inline constexpr uint16_t READ_DELAY_MS  = 100;
  }

  namespace voltage {
      inline constexpr uint8_t CHANNEL_COUNT = 4;
  }

  namespace wind {
      inline constexpr uint16_t SENSOR_DELAY_MS = 100;
  }

  namespace data_logger {
      inline constexpr const char *CSV_PATH = "/data.csv";
      inline constexpr uint32_t LOG_INTERVAL_MS = 5000;
  }

  namespace sleep {
      inline constexpr bool        DEFAULT_ENABLED          = false;
      inline constexpr uint32_t    DEFAULT_DURATION_SECONDS = 300;
      inline constexpr const char* NVS_NAMESPACE            = "sleep";
      inline constexpr const char* ENABLED_KEY             = "enabled";
      inline constexpr const char* DURATION_KEY            = "duration_s";
  }

  namespace provisioning {
      inline constexpr const char* POP           = "ceratina";
      inline constexpr const char* SERVICE_UUID  = "ceaa0001-b5a3-f393-e0a9-e50e24dcca9e";
      inline constexpr const char* CONFIG_UUID   = "ceaa0002-b5a3-f393-e0a9-e50e24dcca9e";
      inline constexpr const char* NVS_NAMESPACE = "prov";
  }

  namespace buttons {
      inline constexpr uint16_t DEBOUNCE_MS    = 50;
      inline constexpr uint16_t LONG_PRESS_MS  = 1000;
  }

  namespace ble {
      inline constexpr uint32_t PASSKEY     = 123456;
      inline constexpr uint8_t  MAX_CLIENTS = 2;
      inline constexpr uint16_t RING_SIZE   = 512;
      inline constexpr uint16_t WRITE_BUF   = 512;
  }

  namespace smtp {
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

  namespace scp {
      inline constexpr uint16_t BUF_SIZE = 4096;
  }

  namespace ws_shell {
      inline constexpr uint16_t RING_SIZE = 512;
      inline constexpr uint16_t WRITE_BUF = 1024;
  }

} // namespace config
