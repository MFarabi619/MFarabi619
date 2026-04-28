#include "sleep_after_poll.h"
#include "sleep.h"
#include <config.h>

#include <Arduino.h>
#include <esp_sleep.h>

namespace {

enum class State {
  INACTIVE,
  WAITING_FOR_DATA,
  WAITING_FOR_DB_POLL,
  SLEEP_REQUESTED,
};

State state = State::INACTIVE;
uint32_t boot_time_ms = 0;
bool is_polled = false;

constexpr uint32_t SENSOR_WARMUP_MS = 10000;

bool is_timer_wakeup() {
  return esp_sleep_get_wakeup_cause() == ESP_SLEEP_WAKEUP_TIMER;
}

bool is_sleep_config_enabled() {
  SleepConfig config = {};
  power::sleep::accessConfig(&config);
  return config.enabled;
}

}

void power::sleep_after_poll::initialize() {
  if (!is_timer_wakeup() || !is_sleep_config_enabled()) {
    state = State::INACTIVE;
    return;
  }

  boot_time_ms = millis();
  is_polled = false;
  state = State::WAITING_FOR_DATA;

  Serial.println("[sleep_after_poll] timer wakeup detected, will sleep after DB poll");
}

void power::sleep_after_poll::notifyPolled() {
  if (state == State::WAITING_FOR_DB_POLL) {
    is_polled = true;
  }
}

void power::sleep_after_poll::service() {
  if (state == State::INACTIVE || state == State::SLEEP_REQUESTED) {
    return;
  }

  uint32_t elapsed_ms = millis() - boot_time_ms;

  if (state == State::WAITING_FOR_DATA && elapsed_ms >= SENSOR_WARMUP_MS) {
    state = State::WAITING_FOR_DB_POLL;
    Serial.println("[sleep_after_poll] sensors ready, waiting for DB poll");
    return;
  }

  if (state == State::WAITING_FOR_DB_POLL) {
    uint32_t max_awake_ms = config::sleep::MAX_AWAKE_SECONDS * 1000;
    bool is_timed_out = elapsed_ms >= max_awake_ms;

    if (is_polled || is_timed_out) {
      if (is_timed_out && !is_polled) {
        Serial.println("[sleep_after_poll] safety timeout, sleeping without poll");
      } else {
        Serial.println("[sleep_after_poll] polled by DB, requesting sleep");
      }

      state = State::SLEEP_REQUESTED;
      SleepCommand command = {.duration_seconds = 0, .ok = false};
      power::sleep::requestConfigured(&command);
    }
  }
}
