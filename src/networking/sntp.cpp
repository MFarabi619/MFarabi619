#include "sntp.h"
#include "../drivers/ds3231.h"

#include <Arduino.h>
#include <time.h>
#include "esp_sntp.h"

static volatile bool synced = false;
static volatile uint32_t synced_epoch = 0;

static void on_time_sync(struct timeval *tv) {
  (void)tv;
  time_t now_utc;
  time(&now_utc);
  synced_epoch = (uint32_t)now_utc;
  synced = true;
  Serial.printf("[ntp] synced, epoch=%lu\n", (unsigned long)now_utc);
}

bool sntp_sync(void) {
  synced = false;
  synced_epoch = 0;

  setenv("TZ", CONFIG_TIME_ZONE, 1);
  tzset();

  sntp_set_time_sync_notification_cb(on_time_sync);
  configTzTime(CONFIG_TIME_ZONE, CONFIG_NTP_SERVER, CONFIG_NTP_SERVER_2);

  uint32_t start = millis();
  while (!synced && (millis() - start) < CONFIG_NTP_SYNC_TIMEOUT_MS) {
    vTaskDelay(pdMS_TO_TICKS(100));
  }

  if (synced && synced_epoch > 0) {
    // Apply to RTC from task context (not from callback)
    ds3231_set_epoch(synced_epoch);
    Serial.printf("[ntp] local time: %s\n", sntp_local_time_string());
  } else {
    Serial.println(F("[ntp] sync timeout — using RTC time"));
  }

  return synced;
}

bool sntp_is_synced(void) {
  return synced;
}

const char *sntp_local_time_string(void) {
  static char buf[32];
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo, 0)) {
    snprintf(buf, sizeof(buf), "(no time)");
    return buf;
  }
  strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S %Z", &timeinfo);
  return buf;
}

uint32_t sntp_utc_epoch(void) {
  time_t now_utc;
  time(&now_utc);
  return (uint32_t)now_utc;
}
