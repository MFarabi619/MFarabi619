#pragma once
#include <config.h>

#include <Arduino.h>

namespace hardware::rs485 {

enum class Channel : uint8_t {
  Bus0 = 0,
  Bus1 = 1,
};

struct BusDescriptor {
  Channel channel;
  HardwareSerial *serial;
  int8_t de_re_gpio;
  uint32_t baud_rate;
  bool ready;
};

bool initialize();
bool accessDescriptor(BusDescriptor *descriptor);

}

