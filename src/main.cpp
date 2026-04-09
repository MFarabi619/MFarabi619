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
  if (!ssh_done) { ssh_server_start(); ssh_done = true; }
  if (!http_done) { http_server_start(); http_done = true; }
}

//------------------------------------------
//  System Task
//------------------------------------------
static void system_task(void *pvParameters) {
  (void)pvParameters;

  Serial.println(F("[system] booting..."));

  // Power on I2C sensor relay and init buses
  pinMode(CONFIG_I2C_RELAY_POWER_GPIO, OUTPUT);
  digitalWrite(CONFIG_I2C_RELAY_POWER_GPIO, HIGH);
  delay(100);
  Wire.begin(CONFIG_I2C_0_SDA_GPIO, CONFIG_I2C_0_SCL_GPIO, CONFIG_I2C_FREQUENCY_KHZ * 1000);
  Wire.setTimeOut(100);
  Wire1.begin(CONFIG_I2C_1_SDA_GPIO, CONFIG_I2C_1_SCL_GPIO, CONFIG_I2C_FREQUENCY_KHZ * 1000);
  Wire1.setTimeOut(100);

  shell_init();

  if (!LittleFS.begin(false)) {
    Serial.println(F("[fs] LittleFS mount failed — NOT formatting to preserve data"));
  } else {
    Serial.printf("[fs] LittleFS: %d/%d KB used\n",
                  LittleFS.usedBytes() / 1024, LittleFS.totalBytes() / 1024);
  }

  if (wifi_connect()) {
    network_services_start();
  } else {
    Serial.println(F("[wifi] not connected — use wifi-set then reboot"));
  }

  // Shell service loop (non-blocking) + SSE heartbeat
  uint32_t last_heartbeat = 0;
  for (;;) {
    shell_service();

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
