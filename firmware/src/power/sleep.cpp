#include "sleep.h"

#include "../hardware/i2c.h"

#include <Arduino.h>
#include <WiFi.h>
#include <esp_sleep.h>

namespace {

bool sleep_pending = false;
uint32_t requested_duration_seconds = 0;
uint32_t request_time_ms = 0;
const char *wake_cause_string = "power_on";

const char *translate_wake_cause(esp_sleep_wakeup_cause_t cause) {
  switch (cause) {
    case ESP_SLEEP_WAKEUP_EXT0: return "ext0";
    case ESP_SLEEP_WAKEUP_EXT1: return "ext1";
    case ESP_SLEEP_WAKEUP_TIMER: return "timer";
    case ESP_SLEEP_WAKEUP_TOUCHPAD: return "touchpad";
    case ESP_SLEEP_WAKEUP_ULP: return "ulp";
    case ESP_SLEEP_WAKEUP_GPIO: return "gpio";
    case ESP_SLEEP_WAKEUP_UART: return "uart";
    case ESP_SLEEP_WAKEUP_WIFI: return "wifi";
    case ESP_SLEEP_WAKEUP_COCPU: return "cocpu";
    case ESP_SLEEP_WAKEUP_COCPU_TRAP_TRIG: return "cocpu_trap";
    case ESP_SLEEP_WAKEUP_BT: return "bluetooth";
    case ESP_SLEEP_WAKEUP_UNDEFINED:
    default: return "power_on";
  }
}

void enter_sleep_now() {
  uint64_t duration_us = static_cast<uint64_t>(requested_duration_seconds) * 1000000ULL;
  esp_sleep_disable_wakeup_source(ESP_SLEEP_WAKEUP_ALL);
  esp_sleep_enable_timer_wakeup(duration_us);

  Serial.printf("[sleep] entering deep sleep for %lu second(s)\n",
                static_cast<unsigned long>(requested_duration_seconds));
  Serial.flush();

  WiFi.mode(WIFI_OFF);
  hardware::i2c::disable();
  delay(50);

  esp_deep_sleep_start();
}

}

void power::sleep::initialize() {
  sleep_pending = false;
  requested_duration_seconds = 0;
  request_time_ms = 0;
  wake_cause_string = translate_wake_cause(esp_sleep_get_wakeup_cause());
}

bool power::sleep::request(SleepCommand *command) {
  if (!command) return false;
  command->ok = false;

  if (command->duration_seconds == 0) {
    return false;
  }

  requested_duration_seconds = command->duration_seconds;
  request_time_ms = millis();
  sleep_pending = true;
  command->ok = true;
  return true;
}

void power::sleep::service() {
  if (!sleep_pending) return;
  if (millis() - request_time_ms < 100) return;
  sleep_pending = false;
  enter_sleep_now();
}

const char *power::sleep::accessWakeCause() {
  return wake_cause_string;
}

bool power::sleep::accessStatus(SleepStatusSnapshot *snapshot) {
  if (!snapshot) return false;
  snapshot->pending = sleep_pending;
  snapshot->requested_duration_seconds = requested_duration_seconds;
  snapshot->wake_cause = wake_cause_string;
  return true;
}
