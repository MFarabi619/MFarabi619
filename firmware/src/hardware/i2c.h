#ifndef HARDWARE_I2C_H
#define HARDWARE_I2C_H

#include <TCA9548.h>
#include <stddef.h>
#include <stdint.h>
#include <Wire.h>

namespace hardware::i2c {

enum class Bus : uint8_t {
  Bus0 = 0,
  Bus1 = 1,
};

struct BusDescriptor {
  Bus bus;
  TwoWire *wire;
  bool ready;
};

struct TopologySnapshot {
  bool legacy_power_enabled;
  bool mux_present;
  uint8_t mux_address;
  bool mux_odd_power_enabled;
  bool mux_even_power_enabled;
};

struct DeviceAccessCommand {
  Bus bus;
  int8_t mux_channel;
  TwoWire *wire;
  bool ok;
};

struct ScanCommand {
  char *buffer;
  size_t capacity;
  int length;
};

extern TCA9548 mux;

void enable();
void disable();
[[nodiscard]] bool isEnabled();

bool initialize();
bool accessBus(BusDescriptor *descriptor);
bool accessTopology(TopologySnapshot *snapshot);
bool accessDevice(DeviceAccessCommand *command);
void clearSelection();
bool scan(ScanCommand *command);

#ifdef PIO_UNIT_TESTING
void test();
#endif

}

#endif
