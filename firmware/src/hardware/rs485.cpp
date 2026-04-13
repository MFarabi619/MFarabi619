#include "rs485.h"

namespace {

struct BusContext {
  hardware::rs485::Channel channel;
  HardwareSerial *serial;
  config::rs485::BusConfig config;
  bool ready;
};

BusContext buses[] = {
  {hardware::rs485::Channel::Bus0, &Serial1, config::rs485::BUS_0, false},
  {hardware::rs485::Channel::Bus1, &Serial2, config::rs485::BUS_1, false},
};

bool initialized = false;

size_t channel_index(hardware::rs485::Channel channel) {
  return static_cast<size_t>(channel);
}

}

bool hardware::rs485::initialize() {
  if (initialized) return true;

  bool ok = true;
  for (size_t index = 0; index < config::rs485::CHANNEL_COUNT; index++) {
    BusContext &context = buses[index];
    pinMode(context.config.de_re_gpio, OUTPUT);
    digitalWrite(context.config.de_re_gpio, LOW);
    context.serial->begin(context.config.baud_rate, SERIAL_8N1,
                          context.config.rx_gpio, context.config.tx_gpio);
    context.ready = true;
  }

  initialized = ok;
  return ok;
}

bool hardware::rs485::accessDescriptor(BusDescriptor *descriptor) {
  if (!descriptor) return false;
  size_t index = channel_index(descriptor->channel);
  if (index >= config::rs485::CHANNEL_COUNT) return false;

  descriptor->serial = buses[index].serial;
  descriptor->de_re_gpio = buses[index].config.de_re_gpio;
  descriptor->baud_rate = buses[index].config.baud_rate;
  descriptor->ready = buses[index].ready;
  return true;
}
