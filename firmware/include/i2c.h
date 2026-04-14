#pragma once

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

struct DiscoveredDevice {
  uint8_t bus;
  uint8_t address;
  int8_t mux_channel;
};

constexpr size_t MAX_DISCOVERED_DEVICES = 32;

const char *deviceNameAt(uint8_t address);

extern TCA9548 mux;

void enable();
void disable();
bool isEnabled();

bool initialize();
bool accessBus(BusDescriptor *descriptor);
bool accessTopology(TopologySnapshot *snapshot);
bool accessDevice(DeviceAccessCommand *command);
void clearSelection();
bool scan(ScanCommand *command);
size_t discoverAll(DiscoveredDevice *devices, size_t capacity);
bool runDiscovery();
bool findDevice(uint8_t address, DiscoveredDevice *result);

#ifdef PIO_UNIT_TESTING
void test();
#endif

}

