#pragma once
#include <config.h>
#include <stdint.h>

namespace networking::sntp {

bool sync();
bool isSynced();
const char *accessLocalTimeString();
uint32_t accessUTCEpoch();

} // namespace networking::sntp

