#include <hal.h>

#include <Arduino.h>

namespace hal::system {

uint32_t freeHeap() {
  return ESP.getFreeHeap();
}

uint32_t minFreeHeap() {
  return ESP.getMinFreeHeap();
}

uint32_t uptimeSeconds() {
  return millis() / 1000;
}

uint32_t uptimeMilliseconds() {
  return millis();
}

}