// clang-format off
#pragma once

// ─────────────────────────────────────────────────────────────────────────────
//  Build flags from platformio.ini (preprocessor injection defaults)
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_WIFI_SSID
#define CONFIG_WIFI_SSID ""
#endif

#ifndef CONFIG_WIFI_PASS
#define CONFIG_WIFI_PASS ""
#endif

#ifndef CONFIG_WIFI_IDENTITY
#define CONFIG_WIFI_IDENTITY ""
#endif

#ifndef CONFIG_WIFI_USERNAME
#define CONFIG_WIFI_USERNAME ""
#endif

#ifndef CONFIG_WIFI_ENTERPRISE
#define CONFIG_WIFI_ENTERPRISE 0
#endif

#ifndef CONFIG_SSH_USER
#define CONFIG_SSH_USER "root"
#endif

#ifndef CONFIG_TUNNEL_DEFAULT_ENABLED
#define CONFIG_TUNNEL_DEFAULT_ENABLED 1
#endif

#ifndef CONFIG_TUNNEL_HOST
#define CONFIG_TUNNEL_HOST ""
#endif

#ifndef CONFIG_TUNNEL_SECRET
#define CONFIG_TUNNEL_SECRET "ceratina"
#endif

#ifndef CONFIG_TUNNEL_REMOTE_PORT
#define CONFIG_TUNNEL_REMOTE_PORT 2098
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  Compile-time feature flags (booleans can't be used in #if)
// ─────────────────────────────────────────────────────────────────────────────

#define CERATINA_TELNET_ENABLED     1
#define CERATINA_OTA_ENABLED        1
#define CERATINA_PROV_ENABLED       0
#define CERATINA_BLE_ENABLED        0
#define CERATINA_SMTP_ENABLED       0
#define CERATINA_SMTP_TEST_ENABLED  0
#define CERATINA_HTTP_AUTH_ENABLED  0
#define CERATINA_TUNNEL_ENABLED         0
#define CERATINA_SLEEP_AFTER_POLL_ENABLED 0
