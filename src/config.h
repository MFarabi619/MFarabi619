// clang-format off
#ifndef CONFIG_H
#define CONFIG_H

// ─────────────────────────────────────────────────────────────────────────────
//  Deployment
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_HOSTNAME
#define CONFIG_HOSTNAME "ceratina"
#endif

#ifndef CONFIG_PLATFORM
#define CONFIG_PLATFORM "esp32s3"
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  Neopixel
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_NEOPIXEL_GPIO
#define CONFIG_NEOPIXEL_GPIO 38
#endif

#ifndef CONFIG_NEOPIXEL_COUNT
#define CONFIG_NEOPIXEL_COUNT 1
#endif

#ifndef CONFIG_NEOPIXEL_BRIGHTNESS
#define CONFIG_NEOPIXEL_BRIGHTNESS 255
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  System
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_SYSTEM_TASK_STACK
#define CONFIG_SYSTEM_TASK_STACK 8192
#endif

#ifndef CONFIG_SERIAL_BAUD
#define CONFIG_SERIAL_BAUD 115200
#endif

#ifndef CONFIG_SHELL_SERVICE_INTERVAL_MS
#define CONFIG_SHELL_SERVICE_INTERVAL_MS 10
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  SSH
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_SSH_PORT
#define CONFIG_SSH_PORT 22
#endif

#ifndef CONFIG_SSH_USER
#define CONFIG_SSH_USER "root"
#endif

// LittleFS-native path (for LittleFS.exists / LittleFS.mkdir)
#ifndef CONFIG_SSH_HOSTKEY_PATH
#define CONFIG_SSH_HOSTKEY_PATH "/.ssh/id_ed25519"
#endif

#ifndef CONFIG_SSH_TASK_STACK
#define CONFIG_SSH_TASK_STACK 32768
#endif

#ifndef CONFIG_SSH_WRITE_BUF_SIZE
#define CONFIG_SSH_WRITE_BUF_SIZE 1024
#endif

#ifndef CONFIG_SSH_RING_SIZE
#define CONFIG_SSH_RING_SIZE 512
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  WiFi
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_WIFI_TIMEOUT_MS
#define CONFIG_WIFI_TIMEOUT_MS 15000
#endif

#ifndef CONFIG_WIFI_POLL_MS
#define CONFIG_WIFI_POLL_MS 100
#endif

#ifndef CONFIG_WIFI_NVS_NAMESPACE
#define CONFIG_WIFI_NVS_NAMESPACE "wifi"
#endif

// ── Access Point (fallback when STA fails) ──

#ifndef CONFIG_AP_SSID
#define CONFIG_AP_SSID "ceratina-access-point"
#endif

#ifndef CONFIG_AP_PASSWORD
#define CONFIG_AP_PASSWORD "apidaesystems"
#endif

#ifndef CONFIG_AP_CHANNEL
#define CONFIG_AP_CHANNEL 1
#endif

#ifndef CONFIG_WIFI_STA_RETRY_MS
#define CONFIG_WIFI_STA_RETRY_MS 10000
#endif

#define CONFIG_WIFI_SSID_IEEE_802_11_MAX_LENGTH 32
#define CONFIG_WIFI_PASS_IEEE_802_11_MAX_LENGTH 64

// ─────────────────────────────────────────────────────────────────────────────
//  Telnet Shell
// ─────────────────────────────────────────────────────────────────────────────

#define CONFIG_TELNET_ENABLED        1
#define CONFIG_TELNET_PORT           23
#define CONFIG_TELNET_RING_SIZE      512
#define CONFIG_TELNET_WRITE_BUF      1024
#define CONFIG_TELNET_KEEPALIVE_MS   3000

// ─────────────────────────────────────────────────────────────────────────────
//  ArduinoOTA
// ─────────────────────────────────────────────────────────────────────────────

#define CONFIG_OTA_ENABLED           0
#define CONFIG_OTA_PORT              3232
#define CONFIG_OTA_PASSWORD          ""
#define CONFIG_OTA_SD_PATH           "/update.bin"

// ─────────────────────────────────────────────────────────────────────────────
//  Time / NTP
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_NTP_SERVER
#define CONFIG_NTP_SERVER "pool.ntp.org"
#endif

#ifndef CONFIG_NTP_SERVER_2
#define CONFIG_NTP_SERVER_2 "time.nist.gov"
#endif

// POSIX TZ string — handles DST automatically
// https://github.com/esp8266/Arduino/blob/master/cores/esp8266/TZ.h
#ifndef CONFIG_TIME_ZONE
#define CONFIG_TIME_ZONE "EST5EDT,M3.2.0/2,M11.1.0/2"
#endif

#ifndef CONFIG_NTP_SYNC_TIMEOUT_MS
#define CONFIG_NTP_SYNC_TIMEOUT_MS 10000
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  HTTP
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_HTTP_PORT
#define CONFIG_HTTP_PORT 80
#endif

#ifndef CONFIG_HTTP_AUTH_ENABLED
#define CONFIG_HTTP_AUTH_ENABLED 0
#endif

#ifndef CONFIG_HTTP_AUTH_USER
#define CONFIG_HTTP_AUTH_USER CONFIG_SSH_USER
#endif

#ifndef CONFIG_HTTP_AUTH_PASSWORD
#define CONFIG_HTTP_AUTH_PASSWORD CONFIG_SSH_USER
#endif

#ifndef CONFIG_HTTP_AUTH_REALM
#define CONFIG_HTTP_AUTH_REALM "ceratina"
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  Shell
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_SHELL_BUF_IN
#define CONFIG_SHELL_BUF_IN 256
#endif

#ifndef CONFIG_SHELL_BUF_OUT
#define CONFIG_SHELL_BUF_OUT 256
#endif

#ifndef CONFIG_SHELL_PATH_MAX
#define CONFIG_SHELL_PATH_MAX 128
#endif

#ifndef CONFIG_SHELL_HOSTNAME_SIZE
#define CONFIG_SHELL_HOSTNAME_SIZE 32
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  I2C
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_I2C_0_SDA_GPIO
#define CONFIG_I2C_0_SDA_GPIO 15
#endif

#ifndef CONFIG_I2C_0_SCL_GPIO
#define CONFIG_I2C_0_SCL_GPIO 16
#endif

#ifndef CONFIG_I2C_1_SDA_GPIO
#define CONFIG_I2C_1_SDA_GPIO 17
#endif

#ifndef CONFIG_I2C_1_SCL_GPIO
#define CONFIG_I2C_1_SCL_GPIO 18
#endif

#ifndef CONFIG_I2C_FREQUENCY_KHZ
#define CONFIG_I2C_FREQUENCY_KHZ 100
#endif

#ifndef CONFIG_I2C_RELAY_POWER_GPIO
#define CONFIG_I2C_RELAY_POWER_GPIO 5
#endif

#define CONFIG_I2C_ADDR_MIN 1
#define CONFIG_I2C_ADDR_MAX 127

#ifndef CONFIG_I2C_MUX_ADDR
#define CONFIG_I2C_MUX_ADDR 0x70
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  EEPROM (AT24C32 on I2C bus 1)
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_EEPROM_I2C_ADDR
#define CONFIG_EEPROM_I2C_ADDR 0x50
#endif

#ifndef CONFIG_EEPROM_PAGE_SIZE
#define CONFIG_EEPROM_PAGE_SIZE 32
#endif

#ifndef CONFIG_EEPROM_TOTAL_SIZE
#define CONFIG_EEPROM_TOTAL_SIZE 4096
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  Temperature / Humidity (SEN0546 / CHT832X behind TCA9548A mux)
//
//  SHT31-compatible wire protocol: write [0x24, 0x00], wait 60ms, read 6 bytes.
//  Sensors discovered dynamically by probing each mux channel for the I2C addr.
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_TEMPERATURE_HUMIDITY_I2C_ADDR
#define CONFIG_TEMPERATURE_HUMIDITY_I2C_ADDR 0x44
#endif

#ifndef CONFIG_TEMPERATURE_HUMIDITY_MAX_SENSORS
#define CONFIG_TEMPERATURE_HUMIDITY_MAX_SENSORS 8
#endif

#ifndef CONFIG_TEMPERATURE_HUMIDITY_READ_DELAY_MS
#define CONFIG_TEMPERATURE_HUMIDITY_READ_DELAY_MS 100
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  Voltage Monitor (ADS1115 on Wire1)
//
//  Adafruit ADS1X15 library. 4-channel single-ended reads via I2C.
//  Mux channel is auto-discovered via tca9548a_find() in ads1115_begin().
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_VOLTAGE_MONITOR_I2C_ADDR
#define CONFIG_VOLTAGE_MONITOR_I2C_ADDR 0x48
#endif

#ifndef CONFIG_VOLTAGE_MONITOR_CHANNEL_COUNT
#define CONFIG_VOLTAGE_MONITOR_CHANNEL_COUNT 4
#endif

// Mux channel is auto-discovered via tca9548a_find() in ads1115_begin()

// ─────────────────────────────────────────────────────────────────────────────
//  SD Card
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_SD_CS_GPIO
#define CONFIG_SD_CS_GPIO 10
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  SCP
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_SCP_BUF_SIZE
#define CONFIG_SCP_BUF_SIZE 4096
#endif

#ifndef CONFIG_WS_SHELL_RING_SIZE
#define CONFIG_WS_SHELL_RING_SIZE 512
#endif

#ifndef CONFIG_WS_SHELL_WRITE_BUF
#define CONFIG_WS_SHELL_WRITE_BUF 1024
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  BLE Provisioning
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_PROV_ENABLED
#define CONFIG_PROV_ENABLED 0
#endif

#ifndef CONFIG_PROV_POP
#define CONFIG_PROV_POP "ceratina"
#endif

#ifndef CONFIG_PROV_SERVICE_UUID
#define CONFIG_PROV_SERVICE_UUID "ceaa0001-b5a3-f393-e0a9-e50e24dcca9e"
#endif

#ifndef CONFIG_PROV_CONFIG_UUID
#define CONFIG_PROV_CONFIG_UUID "ceaa0002-b5a3-f393-e0a9-e50e24dcca9e"
#endif

#ifndef CONFIG_PROV_NVS_NAMESPACE
#define CONFIG_PROV_NVS_NAMESPACE "prov"
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  Physical Buttons (Connector Shield)
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_BUTTON_1_GPIO
#define CONFIG_BUTTON_1_GPIO 35
#endif

#ifndef CONFIG_BUTTON_2_GPIO
#define CONFIG_BUTTON_2_GPIO 4
#endif

#ifndef CONFIG_BUTTON_3_GPIO
#define CONFIG_BUTTON_3_GPIO 42
#endif

#ifndef CONFIG_BUTTON_COUNT
#define CONFIG_BUTTON_COUNT 3
#endif

#ifndef CONFIG_BUTTON_DEBOUNCE_MS
#define CONFIG_BUTTON_DEBOUNCE_MS 50
#endif

#ifndef CONFIG_BUTTON_LONG_PRESS_MS
#define CONFIG_BUTTON_LONG_PRESS_MS 1000
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  BLE Runtime (NUS shell, sensor characteristics)
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_BLE_ENABLED
#define CONFIG_BLE_ENABLED 0
#endif

#ifndef CONFIG_BLE_PASSKEY
#define CONFIG_BLE_PASSKEY 123456
#endif

#ifndef CONFIG_BLE_MAX_CLIENTS
#define CONFIG_BLE_MAX_CLIENTS 2
#endif

#ifndef CONFIG_BLE_RING_SIZE
#define CONFIG_BLE_RING_SIZE 512
#endif

#ifndef CONFIG_BLE_WRITE_BUF
#define CONFIG_BLE_WRITE_BUF 512
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  SMTP Email
//
//  Edit these values directly. Password is stored in NVS (key below).
//  Set CONFIG_SMTP_ENABLED to 1 and fill in your SMTP server details.
// ─────────────────────────────────────────────────────────────────────────────

#define CONFIG_SMTP_ENABLED          0
#define CONFIG_SMTP_HOST             ""
#define CONFIG_SMTP_PORT             587
#define CONFIG_SMTP_DOMAIN           ""
#define CONFIG_SMTP_FROM_EMAIL       ""
#define CONFIG_SMTP_FROM_NAME        ""
#define CONFIG_SMTP_TO_EMAIL         ""
#define CONFIG_SMTP_LOGIN_EMAIL      ""
#define CONFIG_SMTP_SUBJECT_PREFIX   "[ceratina]"
#define CONFIG_SMTP_AUTH_ENABLED     0
#define CONFIG_SMTP_SSL_ENABLED      0
#define CONFIG_SMTP_STARTTLS_ENABLED 0
#define CONFIG_SMTP_TEST_ENABLED     0
#define CONFIG_SMTP_NVS_KEY          "SMTP_PASSWORD"

// ─────────────────────────────────────────────────────────────────────────────
//  CloudEvents
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_CLOUDEVENTS_TENANT
#define CONFIG_CLOUDEVENTS_TENANT "default-tenant"
#endif

#ifndef CONFIG_CLOUDEVENTS_SITE
#define CONFIG_CLOUDEVENTS_SITE "default-site"
#endif

#endif // CONFIG_H
