#ifndef HARDWARE_I2C_H
#define HARDWARE_I2C_H

#include <TCA9548.h>
#include <stddef.h>

namespace hardware::i2c {

extern TCA9548 mux;

void enable() noexcept;
void disable() noexcept;
[[nodiscard]] bool isEnabled() noexcept;

bool initialize() noexcept;
int scan(char *buf, size_t buf_size) noexcept;

#ifdef PIO_UNIT_TESTING
void test() noexcept;
#endif

}

#endif
