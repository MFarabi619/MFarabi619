#ifndef CONFIG_H
#define CONFIG_H

// ─────────────────────────────────────────────────────────────────────────────
//  Deployment
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_HOSTNAME
#define CONFIG_HOSTNAME             "microvisor"
#endif

#ifndef CONFIG_PLATFORM
#define CONFIG_PLATFORM             "esp32s3"
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  System
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_SYSTEM_TASK_STACK
#define CONFIG_SYSTEM_TASK_STACK    8192
#endif

#ifndef CONFIG_SERIAL_BAUD
#define CONFIG_SERIAL_BAUD          115200
#endif

#ifndef CONFIG_SHELL_SERVICE_INTERVAL_MS
#define CONFIG_SHELL_SERVICE_INTERVAL_MS 10
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  SSH
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_SSH_PORT
#define CONFIG_SSH_PORT             22
#endif

#ifndef CONFIG_SSH_USER
#define CONFIG_SSH_USER             "root"
#endif

#ifndef CONFIG_SSH_HOSTKEY_PATH
#define CONFIG_SSH_HOSTKEY_PATH     "/littlefs/.ssh/id_ed25519"
#endif

#ifndef CONFIG_SSH_BUF_SIZE
#define CONFIG_SSH_BUF_SIZE         2048
#endif

#ifndef CONFIG_SSH_TASK_STACK
#define CONFIG_SSH_TASK_STACK       32768
#endif

#ifndef CONFIG_SSH_WRITE_BUF_SIZE
#define CONFIG_SSH_WRITE_BUF_SIZE   1024
#endif

#ifndef CONFIG_SSH_RING_SIZE
#define CONFIG_SSH_RING_SIZE        512
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  WiFi
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_WIFI_TIMEOUT_MS
#define CONFIG_WIFI_TIMEOUT_MS      15000
#endif

#ifndef CONFIG_WIFI_POLL_MS
#define CONFIG_WIFI_POLL_MS         100
#endif

#ifndef CONFIG_WIFI_NVS_NAMESPACE
#define CONFIG_WIFI_NVS_NAMESPACE   "wifi"
#endif

#ifndef CONFIG_WIFI_AP_SSID
#define CONFIG_WIFI_AP_SSID         "ceratina-setup"
#endif

#ifndef CONFIG_WIFI_AP_PASSWORD
#define CONFIG_WIFI_AP_PASSWORD     "changeme123"
#endif

#define CONFIG_WIFI_SSID_IEEE_802_11_MAX_LENGTH  32
#define CONFIG_WIFI_PASS_IEEE_802_11_MAX_LENGTH  64

// ─────────────────────────────────────────────────────────────────────────────
//  Time / NTP
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_NTP_SERVER
#define CONFIG_NTP_SERVER           "pool.ntp.org"
#endif

#ifndef CONFIG_NTP_SERVER_2
#define CONFIG_NTP_SERVER_2         "time.nist.gov"
#endif

// POSIX TZ string — handles DST automatically
// https://github.com/esp8266/Arduino/blob/master/cores/esp8266/TZ.h
#ifndef CONFIG_TIME_ZONE
#define CONFIG_TIME_ZONE            "EST5EDT,M3.2.0/2,M11.1.0/2"
#endif

#ifndef CONFIG_NTP_SYNC_TIMEOUT_MS
#define CONFIG_NTP_SYNC_TIMEOUT_MS  10000
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  HTTP
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_HTTP_PORT
#define CONFIG_HTTP_PORT            80
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  Shell
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_SHELL_BUF_IN
#define CONFIG_SHELL_BUF_IN         256
#endif

#ifndef CONFIG_SHELL_BUF_OUT
#define CONFIG_SHELL_BUF_OUT        256
#endif

#ifndef CONFIG_SHELL_PATH_MAX
#define CONFIG_SHELL_PATH_MAX       128
#endif

#ifndef CONFIG_SHELL_HOSTNAME_SIZE
#define CONFIG_SHELL_HOSTNAME_SIZE  32
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  I2C
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_I2C_0_SDA_GPIO
#define CONFIG_I2C_0_SDA_GPIO       15
#endif

#ifndef CONFIG_I2C_0_SCL_GPIO
#define CONFIG_I2C_0_SCL_GPIO       16
#endif

#ifndef CONFIG_I2C_1_SDA_GPIO
#define CONFIG_I2C_1_SDA_GPIO       17
#endif

#ifndef CONFIG_I2C_1_SCL_GPIO
#define CONFIG_I2C_1_SCL_GPIO       18
#endif

#ifndef CONFIG_I2C_FREQUENCY_KHZ
#define CONFIG_I2C_FREQUENCY_KHZ    100
#endif

#ifndef CONFIG_I2C_RELAY_POWER_GPIO
#define CONFIG_I2C_RELAY_POWER_GPIO 5
#endif

#define CONFIG_I2C_ADDR_MIN         1
#define CONFIG_I2C_ADDR_MAX         127

// ─────────────────────────────────────────────────────────────────────────────
//  SD Card
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_SD_CS_GPIO
#define CONFIG_SD_CS_GPIO           10
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  SCP
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_SCP_BUF_SIZE
#define CONFIG_SCP_BUF_SIZE         4096
#endif

#endif // CONFIG_H
