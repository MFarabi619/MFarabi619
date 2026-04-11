#include "buttons.h"
#include "../config.h"

#include <Arduino.h>

static const uint8_t button_gpios[CONFIG_BUTTON_COUNT] = {
  CONFIG_BUTTON_1_GPIO,
  CONFIG_BUTTON_2_GPIO,
  CONFIG_BUTTON_3_GPIO,
};

static volatile uint32_t last_press_ms[CONFIG_BUTTON_COUNT] = {0};
static volatile bool pending_press[CONFIG_BUTTON_COUNT] = {false};
static uint32_t press_start_ms[CONFIG_BUTTON_COUNT] = {0};
static bool was_pressed[CONFIG_BUTTON_COUNT] = {false};

static button_callback_t on_press_cb = nullptr;
static button_callback_t on_long_press_cb = nullptr;

static void IRAM_ATTR button_isr(void *arg) {
  uint8_t index = (uint8_t)(uintptr_t)arg;
  uint32_t now = millis();
  if (now - last_press_ms[index] > CONFIG_BUTTON_DEBOUNCE_MS) {
    last_press_ms[index] = now;
    pending_press[index] = true;
  }
}

void buttons_init(void) {
  for (uint8_t i = 0; i < CONFIG_BUTTON_COUNT; i++) {
    pinMode(button_gpios[i], INPUT);
    attachInterruptArg(
        digitalPinToInterrupt(button_gpios[i]),
        button_isr,
        (void *)(uintptr_t)i,
        FALLING);
  }
  Serial.printf("[buttons] initialized %d buttons (GPIO %d, %d, %d)\n",
                CONFIG_BUTTON_COUNT,
                CONFIG_BUTTON_1_GPIO, CONFIG_BUTTON_2_GPIO, CONFIG_BUTTON_3_GPIO);
}

void buttons_service(void) {
  for (uint8_t i = 0; i < CONFIG_BUTTON_COUNT; i++) {
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

      if (held >= CONFIG_BUTTON_LONG_PRESS_MS) {
        if (on_long_press_cb) on_long_press_cb(i);
      } else {
        if (on_press_cb) on_press_cb(i);
      }
    }
  }
}

void buttons_on_press(button_callback_t cb) { on_press_cb = cb; }
void buttons_on_long_press(button_callback_t cb) { on_long_press_cb = cb; }

bool buttons_is_pressed(uint8_t index) {
  if (index >= CONFIG_BUTTON_COUNT) return false;
  return !digitalRead(button_gpios[index]);
}
