#ifndef NETWORKING_WIFI_H
#define NETWORKING_WIFI_H

#include "../config.h"
#include <stddef.h>

struct APConfig {
    char ssid[33];
    char password[65];
};

namespace networking::wifi::sta {

void initialize() noexcept;
[[nodiscard]] bool connect() noexcept;

} // namespace networking::wifi::sta

namespace networking::wifi::ap {

void enable() noexcept;
void disable() noexcept;
[[nodiscard]] bool isActive() noexcept;
void accessConfig(APConfig *config) noexcept;
void configure(const char *ssid, const char *password) noexcept;

} // namespace networking::wifi::ap

#endif // NETWORKING_WIFI_H
