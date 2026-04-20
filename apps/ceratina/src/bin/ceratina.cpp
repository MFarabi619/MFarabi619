#include <boot/system.h>
#include <config.h>
#include <networking/wifi.h>
#include <Arduino.h>

#ifndef PIO_UNIT_TESTING

void setup(void) {
  Serial.begin(config::system::SERIAL_BAUD);
  delay(100);

  networking::wifi::sta::initialize();
  boot::system::startTask();
}

void loop(void) {}

#endif
