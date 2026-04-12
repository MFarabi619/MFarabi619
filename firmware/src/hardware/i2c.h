#ifndef HARDWARE_I2C_H
#define HARDWARE_I2C_H

#include <TCA9548.h>
#include <stddef.h>

namespace hardware::i2c {

struct ScanCommand {
  char *buffer;
  size_t capacity;
  int length;
};

extern TCA9548 mux;

void enable() noexcept;
void disable() noexcept;
[[nodiscard]] bool isEnabled() noexcept;

bool initialize() noexcept;
bool scan(ScanCommand *command) noexcept;

#ifdef PIO_UNIT_TESTING
void test() noexcept;
#endif

}

#endif
