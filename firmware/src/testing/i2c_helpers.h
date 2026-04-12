#ifndef TESTING_I2C_HELPERS_H
#define TESTING_I2C_HELPERS_H

#ifdef PIO_UNIT_TESTING

#include "../config.h"
#include "../hardware/i2c.h"
#include <Arduino.h>
#include <Wire.h>

static inline void test_ensure_wire0(void) {
  Wire.begin(config::i2c::BUS_0.sda_gpio, config::i2c::BUS_0.scl_gpio,
             config::i2c::FREQUENCY_KHZ * 1000);
  Wire.setTimeOut(100);
}

static inline void test_ensure_wire1(void) {
  Wire1.begin(config::i2c::BUS_1.sda_gpio, config::i2c::BUS_1.scl_gpio,
              config::i2c::FREQUENCY_KHZ * 1000);
  Wire1.setTimeOut(100);
}

static inline void test_ensure_wire1_with_power(void) {
  hardware::i2c::enable();
  test_ensure_wire1();
}

#endif
#endif
