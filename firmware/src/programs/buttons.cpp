#include "buttons.h"
#include "../config.h"

#include <Arduino.h>

static const int8_t button_gpios[config::buttons::COUNT] = {
  config::buttons::GPIO_1,
  config::buttons::GPIO_2,
  config::buttons::GPIO_3,
};

static volatile uint32_t last_press_ms[config::buttons::COUNT] = {0};
static volatile bool pending_press[config::buttons::COUNT] = {false};
static uint32_t press_start_ms[config::buttons::COUNT] = {0};
static bool was_pressed[config::buttons::COUNT] = {false};

static ButtonCallback on_press_cb = nullptr;
static ButtonCallback on_long_press_cb = nullptr;

static void IRAM_ATTR button_isr(void *arg) {
  uint8_t index = (uint8_t)(uintptr_t)arg;
  uint32_t now = millis();
  if (now - last_press_ms[index] > config::buttons::DEBOUNCE_MS) {
    last_press_ms[index] = now;
    pending_press[index] = true;
  }
}

void programs::buttons::initialize() {
  for (uint8_t i = 0; i < config::buttons::COUNT; i++) {
    if ((int8_t)button_gpios[i] < 0) continue;
    pinMode(button_gpios[i], INPUT);
    attachInterruptArg(
        digitalPinToInterrupt(button_gpios[i]),
        button_isr,
        (void *)(uintptr_t)i,
        FALLING);
  }
  Serial.printf("[buttons] initialized %d buttons (GPIO %d, %d, %d)\n",
                config::buttons::COUNT,
                config::buttons::GPIO_1, config::buttons::GPIO_2, config::buttons::GPIO_3);
}

void programs::buttons::service() {
  for (uint8_t i = 0; i < config::buttons::COUNT; i++) {
    if ((int8_t)button_gpios[i] < 0) continue;
    bool pressed = !digitalRead(button_gpios[i]);

    if (pending_press[i]) {
      pending_press[i] = false;
      if (!was_pressed[i]) {
        press_start_ms[i] = millis();
        was_pressed[i] = true;
      }
    }

    if (was_pressed[i] && !pressed) {
      uint32_t held = millis() - press_start_ms[i];
      was_pressed[i] = false;

      if (held >= config::buttons::LONG_PRESS_MS) {
        if (on_long_press_cb) on_long_press_cb(i);
      } else {
        if (on_press_cb) on_press_cb(i);
      }
    }
  }
}

void programs::buttons::onPress(ButtonCallback cb) { on_press_cb = cb; }
void programs::buttons::onLongPress(ButtonCallback cb) { on_long_press_cb = cb; }

bool programs::buttons::isPressed(uint8_t index) {
  if (index >= config::buttons::COUNT) return false;
  return !digitalRead(button_gpios[index]);
}
