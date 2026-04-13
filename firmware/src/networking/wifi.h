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

void configureHostname(const char *hostname);
bool accessSnapshot(NetworkStatusSnapshot *snapshot);
bool accessConfig(WifiSavedConfig *config);
bool storeConfig(WifiSavedConfig *config);
bool connect(WifiConnectCommand *command);
bool scan(WifiScanCommand *command);

#ifdef PIO_UNIT_TESTING
void test(void);
#endif

} // namespace networking::wifi

namespace networking::wifi::sta {

void initialize();
[[nodiscard]] bool connect();

} // namespace networking::wifi::sta

namespace networking::wifi::ap {

void enable();
void disable();
[[nodiscard]] bool isActive();
void accessConfig(APConfig *config);
bool accessSnapshot(APSnapshot *snapshot);
bool applyConfig(APConfigureCommand *command);
bool setEnabled(APEnabledCommand *command);

} // namespace networking::wifi::ap

#endif // NETWORKING_WIFI_H
