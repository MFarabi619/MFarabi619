//------------------------------------------
//  Includes
//------------------------------------------
#include "config.h"

#include <Arduino.h>
#include <LittleFS.h>
#include <Wire.h>

#include "networking/wifi.h"
#include "networking/sntp.h"
#include "services/http.h"
#include "services/network.h"
#include "services/temperature_and_humidity.h"
#include "services/ws_shell.h"
#include "drivers/neopixel.h"
#include "drivers/tca9548a.h"
#include "drivers/ads1115.h"
#include "programs/ssh/ssh_server.h"
#include "programs/shell/shell.h"

//------------------------------------------
//  Network Services (idempotent — safe to call multiple times)
//------------------------------------------
void network_services_start(void) {
  static bool sntp_done = false;
  static bool ssh_done = false;
  static bool http_done = false;

  if (!sntp_done) sntp_done = sntp_sync();
  if (!ssh_done) ssh_done = ssh_server_start();
  if (!http_done) { http_server_start(); http_done = true; }
}

//------------------------------------------
//  System Task
//------------------------------------------
static void system_task(void *pvParameters) {
  (void)pvParameters;

  Serial.println(F("[system] booting..."));

  neopixel_init();
  neopixel_blue();

  // Power on I2C sensor relay and init buses
  pinMode(CONFIG_I2C_RELAY_POWER_GPIO, OUTPUT);
  digitalWrite(CONFIG_I2C_RELAY_POWER_GPIO, HIGH);
  delay(100);
  Wire.begin(CONFIG_I2C_0_SDA_GPIO, CONFIG_I2C_0_SCL_GPIO, CONFIG_I2C_FREQUENCY_KHZ * 1000);
  Wire.setTimeOut(100);
  Wire1.begin(CONFIG_I2C_1_SDA_GPIO, CONFIG_I2C_1_SCL_GPIO, CONFIG_I2C_FREQUENCY_KHZ * 1000);
  Wire1.setTimeOut(100);

  // Discover sensors behind TCA9548A mux
  tca9548a_init();
  temperature_and_humidity_discover();
  ads1115_init();
  ads1115_begin();

  shell_init();

  if (!LittleFS.begin(false)) {
    Serial.println(F("[fs] mount failed, formatting..."));
    neopixel_red();
    if (!LittleFS.begin(true)) {
      Serial.println(F("[fs] format failed — filesystem unavailable"));
    }
  }
  if (LittleFS.totalBytes() > 0) {
    Serial.printf("[fs] LittleFS: %u/%u KB used\n",
                  (unsigned)(LittleFS.usedBytes() / 1024),
                  (unsigned)(LittleFS.totalBytes() / 1024));
    neopixel_blue();
  }

  // AP always on by default (configurable via UI)
  if (wifi_get_ap_enabled()) {
    wifi_start_ap();
  }

  if (wifi_connect()) {
    neopixel_green();
  } else {
    Serial.println(F("[wifi] STA not connected — AP available for provisioning"));
    neopixel_yellow();
  }

  network_services_start();

  // Shell service loop (non-blocking) + SSE heartbeat + DNS
  uint32_t last_heartbeat = 0;
  for (;;) {
    shell_service();
    wifi_dns_service();
    ws_shell_service();

    if (millis() - last_heartbeat > 5000) {
      last_heartbeat = millis();
      char buf[64];
      snprintf(buf, sizeof(buf), "{\"uptime\":%lu,\"heap\":%u}",
               millis() / 1000, ESP.getFreeHeap());
      http_events.send(buf, "heartbeat", millis());
    }

    vTaskDelay(pdMS_TO_TICKS(CONFIG_SHELL_SERVICE_INTERVAL_MS));
  }
}

//------------------------------------------
//  Arduino Entry Points
//------------------------------------------
#ifndef PIO_UNIT_TESTING

void setup(void) {
  Serial.begin(CONFIG_SERIAL_BAUD);
  delay(100);

  wifi_setup();

  xTaskCreatePinnedToCore(system_task, "system", CONFIG_SYSTEM_TASK_STACK, NULL,
                          1, NULL, 1);
}

void loop(void) {}

#endif
