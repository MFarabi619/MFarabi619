#ifndef NETWORKING_SNTP_H
#define NETWORKING_SNTP_H

#include "../config.h"
#include <stdint.h>

namespace networking::sntp {

bool sync();
[[nodiscard]] bool isSynced();
[[nodiscard]] const char *accessLocalTimeString();
[[nodiscard]] uint32_t accessUTCEpoch();

} // namespace networking::sntp

#endif // NETWORKING_SNTP_H
