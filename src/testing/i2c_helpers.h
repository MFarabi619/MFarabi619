#ifndef TESTING_I2C_HELPERS_H
#define TESTING_I2C_HELPERS_H

#ifdef PIO_UNIT_TESTING

#include "../config.h"
#include <Arduino.h>
#include <Wire.h>

static inline void test_ensure_wire0(void) {
  Wire.begin(CONFIG_I2C_0_SDA_GPIO, CONFIG_I2C_0_SCL_GPIO,
             CONFIG_I2C_FREQUENCY_KHZ * 1000);
  Wire.setTimeOut(100);
}

static inline void test_ensure_wire1(void) {
  Wire1.begin(CONFIG_I2C_1_SDA_GPIO, CONFIG_I2C_1_SCL_GPIO,
              CONFIG_I2C_FREQUENCY_KHZ * 1000);
  Wire1.setTimeOut(100);
}

static inline void test_ensure_wire1_with_power(void) {
  pinMode(CONFIG_I2C_RELAY_POWER_GPIO, OUTPUT);
  digitalWrite(CONFIG_I2C_RELAY_POWER_GPIO, HIGH);
  delay(100);
  test_ensure_wire1();
}

#endif
#endif
