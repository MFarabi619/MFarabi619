#ifndef NETWORKING_WIFI_H
#define NETWORKING_WIFI_H

#include "../config.h"
#include <stddef.h>
#include <stdint.h>

struct APConfig {
    char ssid[33];
    char password[65];
};

struct APSnapshot {
    bool active;
    char ssid[33];
    char password[65];
    char ip[16];
    uint16_t clients;
    char hostname[config::shell::HOSTNAME_SIZE + 1];
    char mac[18];
};

struct NetworkStatusSnapshot {
    bool connected;
    char ssid[33];
    char bssid[18];
    int32_t rssi;
    int32_t channel;
    char ip[16];
    char gateway[16];
    char subnet[16];
    char dns[16];
    char mac[18];
    char hostname[config::shell::HOSTNAME_SIZE + 1];
    APSnapshot ap;
};

struct WifiConnectRequest {
    const char *ssid;
    const char *password;
    bool enable_ap_fallback;
};

struct WifiConnectResult {
    bool connected;
    int status_code;
    bool ap_enabled_for_fallback;
};

struct WifiScanResult {
    char ssid[33];
    char bssid[18];
    int32_t rssi;
    int32_t channel;
    char encryption[24];
    bool open;
};

struct WifiSavedConfig {
    char ssid[33];
    char password[65];
    bool valid;
};

struct WifiConnectCommand {
    WifiConnectRequest request;
    WifiConnectResult result;
};

struct WifiScanCommand {
    WifiScanResult *results;
    size_t max_results;
    int result_count;
};

struct APConfigureCommand {
    APConfig config;
    APSnapshot snapshot;
};

struct APEnabledCommand {
    bool enabled;
    APSnapshot snapshot;
};

namespace networking::wifi {

void configureHostname(const char *hostname) noexcept;
bool accessSnapshot(NetworkStatusSnapshot *snapshot) noexcept;
bool accessConfig(WifiSavedConfig *config) noexcept;
bool storeConfig(WifiSavedConfig *config) noexcept;
bool connect(WifiConnectCommand *command) noexcept;
bool scan(WifiScanCommand *command) noexcept;

#ifdef PIO_UNIT_TESTING
void test(void);
#endif

} // namespace networking::wifi

namespace networking::wifi::sta {

void initialize() noexcept;
[[nodiscard]] bool connect() noexcept;

} // namespace networking::wifi::sta

namespace networking::wifi::ap {

void enable() noexcept;
void disable() noexcept;
[[nodiscard]] bool isActive() noexcept;
void accessConfig(APConfig *config) noexcept;
bool accessSnapshot(APSnapshot *snapshot) noexcept;
bool applyConfig(APConfigureCommand *command) noexcept;
bool setEnabled(APEnabledCommand *command) noexcept;

} // namespace networking::wifi::ap

#endif // NETWORKING_WIFI_H
