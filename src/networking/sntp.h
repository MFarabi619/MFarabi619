#ifndef NETWORKING_SNTP_H
#define NETWORKING_SNTP_H

#include "../config.h"
#include <stdint.h>

namespace networking::sntp {

bool sync() noexcept;
[[nodiscard]] bool isSynced() noexcept;
[[nodiscard]] const char *accessLocalTimeString() noexcept;
[[nodiscard]] uint32_t accessUTCEpoch() noexcept;

} // namespace networking::sntp

#endif // NETWORKING_SNTP_H
