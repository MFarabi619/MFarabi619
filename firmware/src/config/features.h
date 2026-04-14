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

#ifndef CONFIG_SSH_USER
#define CONFIG_SSH_USER "root"
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  Compile-time feature flags (booleans can't be used in #if)
// ─────────────────────────────────────────────────────────────────────────────

#define CERATINA_TELNET_ENABLED     1
#define CERATINA_OTA_ENABLED        0
#define CERATINA_PROV_ENABLED       0
#define CERATINA_BLE_ENABLED        0
#define CERATINA_SMTP_ENABLED       0
#define CERATINA_SMTP_TEST_ENABLED  0
#define CERATINA_HTTP_AUTH_ENABLED   0
