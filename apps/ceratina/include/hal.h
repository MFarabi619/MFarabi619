#pragma once

#include <cstdint>

namespace hal::system {

uint32_t freeHeap();
uint32_t minFreeHeap();
uint32_t uptimeSeconds();
uint32_t uptimeMilliseconds();

}