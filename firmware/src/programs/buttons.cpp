#include "buttons.h"
#include <config.h>

#include <OneButton.h>
#include <Arduino.h>

namespace {

const int8_t gpios[config::buttons::COUNT] = {
  config::buttons::GPIO_1,
  config::buttons::GPIO_2,
  config::buttons::GPIO_3,
};

OneButton instances[config::buttons::COUNT];

ButtonCallback on_press_cb = nullptr;
ButtonCallback on_click_cb = nullptr;
ButtonCallback on_double_click_cb = nullptr;
ButtonCallback on_multi_click_cb = nullptr;
ButtonCallback on_long_press_start_cb = nullptr;
ButtonCallback on_long_press_stop_cb = nullptr;
ButtonCallback on_during_long_press_cb = nullptr;
IdleCallback on_idle_cb = nullptr;

void route_press(void *p) {
  if (on_press_cb) on_press_cb((uint8_t)(uintptr_t)p);
}

void route_click(void *p) {
  if (on_click_cb) on_click_cb((uint8_t)(uintptr_t)p);
}

void route_double_click(void *p) {
  if (on_double_click_cb) on_double_click_cb((uint8_t)(uintptr_t)p);
}

void route_multi_click(void *p) {
  if (on_multi_click_cb) on_multi_click_cb((uint8_t)(uintptr_t)p);
}

void route_long_press_start(void *p) {
  if (on_long_press_start_cb) on_long_press_start_cb((uint8_t)(uintptr_t)p);
}

void route_long_press_stop(void *p) {
  if (on_long_press_stop_cb) on_long_press_stop_cb((uint8_t)(uintptr_t)p);
}

void route_during_long_press(void *p) {
  if (on_during_long_press_cb) on_during_long_press_cb((uint8_t)(uintptr_t)p);
}

void route_idle() {
  if (on_idle_cb) on_idle_cb();
}

}

void programs::buttons::initialize() {
  uint8_t active = 0;
  for (uint8_t i = 0; i < config::buttons::COUNT; i++) {
    if (gpios[i] < 0) continue;
    instances[i].setup(gpios[i], INPUT, true);
    instances[i].setDebounceMs(config::buttons::DEBOUNCE_MS);
    instances[i].setPressMs(config::buttons::LONG_PRESS_MS);
    instances[i].attachPress(route_press, (void *)(uintptr_t)i);
    instances[i].attachClick(route_click, (void *)(uintptr_t)i);
    instances[i].attachDoubleClick(route_double_click, (void *)(uintptr_t)i);
    instances[i].attachMultiClick(route_multi_click, (void *)(uintptr_t)i);
    instances[i].attachLongPressStart(route_long_press_start, (void *)(uintptr_t)i);
    instances[i].attachLongPressStop(route_long_press_stop, (void *)(uintptr_t)i);
    instances[i].attachDuringLongPress(route_during_long_press, (void *)(uintptr_t)i);
    instances[i].attachIdle(route_idle);
    active++;
  }
  Serial.printf("[buttons] %d active (GPIO %d, %d, %d)\n",
                active,
                config::buttons::GPIO_1, config::buttons::GPIO_2, config::buttons::GPIO_3);
}

void programs::buttons::service() {
  for (uint8_t i = 0; i < config::buttons::COUNT; i++) {
    if (gpios[i] < 0) continue;
    instances[i].tick();
  }
}

void programs::buttons::onPress(ButtonCallback cb)            { on_press_cb = cb; }
void programs::buttons::onClick(ButtonCallback cb)            { on_click_cb = cb; }
void programs::buttons::onDoubleClick(ButtonCallback cb)      { on_double_click_cb = cb; }
void programs::buttons::onMultiClick(ButtonCallback cb)       { on_multi_click_cb = cb; }
void programs::buttons::onLongPressStart(ButtonCallback cb)   { on_long_press_start_cb = cb; }
void programs::buttons::onLongPressStop(ButtonCallback cb)    { on_long_press_stop_cb = cb; }
void programs::buttons::onDuringLongPress(ButtonCallback cb)  { on_during_long_press_cb = cb; }
void programs::buttons::onIdle(IdleCallback cb)               { on_idle_cb = cb; }

void programs::buttons::setClickMs(unsigned int ms) {
  for (uint8_t i = 0; i < config::buttons::COUNT; i++) {
    if (gpios[i] < 0) continue;
    instances[i].setClickMs(ms);
  }
}

void programs::buttons::setIdleMs(unsigned int ms) {
  for (uint8_t i = 0; i < config::buttons::COUNT; i++) {
    if (gpios[i] < 0) continue;
    instances[i].setIdleMs(ms);
  }
}

void programs::buttons::setLongPressIntervalMs(unsigned int ms) {
  for (uint8_t i = 0; i < config::buttons::COUNT; i++) {
    if (gpios[i] < 0) continue;
    instances[i].setLongPressIntervalMs(ms);
  }
}

bool programs::buttons::isPressed(uint8_t index) {
  if (index >= config::buttons::COUNT) return false;
  if (gpios[index] < 0) return false;
  return !digitalRead(gpios[index]);
}

bool programs::buttons::isIdle(uint8_t index) {
  if (index >= config::buttons::COUNT) return false;
  if (gpios[index] < 0) return true;
  return instances[index].isIdle();
}

bool programs::buttons::isLongPressed(uint8_t index) {
  if (index >= config::buttons::COUNT) return false;
  if (gpios[index] < 0) return false;
  return instances[index].isLongPressed();
}

unsigned long programs::buttons::getPressedMs(uint8_t index) {
  if (index >= config::buttons::COUNT) return 0;
  if (gpios[index] < 0) return 0;
  return instances[index].getPressedMs();
}

int programs::buttons::getNumberClicks(uint8_t index) {
  if (index >= config::buttons::COUNT) return 0;
  if (gpios[index] < 0) return 0;
  return instances[index].getNumberClicks();
}

void programs::buttons::reset(uint8_t index) {
  if (index >= config::buttons::COUNT) return;
  if (gpios[index] < 0) return;
  instances[index].reset();
}

#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

static void buttons_test_config_valid(void) {
  TEST_MESSAGE("user verifies button GPIO configuration");

  TEST_ASSERT_EQUAL_INT_MESSAGE(3, config::buttons::COUNT,
      "device: should have 3 button slots");
  TEST_ASSERT_EQUAL_INT_MESSAGE(-1, config::buttons::GPIO_1,
      "device: GPIO_1 should be -1 (reserved for PSRAM)");
  TEST_ASSERT_GREATER_OR_EQUAL_INT_MESSAGE(0, config::buttons::GPIO_2,
      "device: GPIO_2 should be a valid pin");
  TEST_ASSERT_GREATER_OR_EQUAL_INT_MESSAGE(0, config::buttons::GPIO_3,
      "device: GPIO_3 should be a valid pin");

  char msg[64];
  snprintf(msg, sizeof(msg), "debounce=%dms long_press=%dms",
           config::buttons::DEBOUNCE_MS, config::buttons::LONG_PRESS_MS);
  TEST_MESSAGE(msg);
}

static void buttons_test_disabled_gpio_rejected(void) {
  TEST_MESSAGE("user checks that disabled GPIO returns false for isPressed");
  TEST_ASSERT_FALSE_MESSAGE(programs::buttons::isPressed(0),
      "device: button 0 (GPIO -1) should always return false");
}

static void buttons_test_out_of_range_rejected(void) {
  TEST_MESSAGE("user checks that out-of-range index returns false");
  TEST_ASSERT_FALSE_MESSAGE(programs::buttons::isPressed(255),
      "device: index 255 should return false");
}

void programs::buttons::test() {
  it("user verifies button GPIO configuration", buttons_test_config_valid);
  it("user checks that disabled GPIO returns false", buttons_test_disabled_gpio_rejected);
  it("user checks that out-of-range index is rejected", buttons_test_out_of_range_rejected);
}

#endif
