#ifndef NETWORKING_TELNET_H
#define NETWORKING_TELNET_H

#include "../config.h"

namespace networking::telnet {

void initialize() noexcept;
void service() noexcept;
[[nodiscard]] bool isConnected() noexcept;
[[nodiscard]] const char *clientIP() noexcept;
void disconnect() noexcept;

} // namespace networking::telnet

#endif
