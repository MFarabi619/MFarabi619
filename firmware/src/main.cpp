//------------------------------------------
//  Includes
//------------------------------------------
#include "config.h"
#include "hardware/i2c.h"

#include <Arduino.h>
#include <LittleFS.h>
#include <Wire.h>

#include "networking/wifi.h"
#include "networking/sntp.h"
#include "networking/telnet.h"
#include "networking/ota.h"
#include "networking/update.h"
#include "services/http.h"
#include "sensors/temperature_and_humidity.h"
#include "services/ws_shell.h"
#include "sensors/carbon_dioxide.h"
#include "networking/ble.h"
#include "networking/provisioning.h"
#include "programs/buttons.h"
#include "programs/led.h"
#include <ColorFormat.h>
#include "sensors/voltage.h"
#include "programs/ssh/ssh_server.h"
#include "programs/shell/shell.h"

//------------------------------------------
//  Network Services (idempotent — safe to call multiple times)
//------------------------------------------
void network_services_start(void) {
  static bool sntp_done = false;
  static bool ssh_done = false;
  static bool http_done = false;
  static bool telnet_done = false;
  static bool ota_done = false;

  if (!sntp_done) sntp_done = networking::sntp::sync();
  if (!ssh_done) ssh_done = services::sshd::initialize();
  if (!http_done) { services::http::initialize(); http_done = true; }
  if (!telnet_done) { networking::telnet::initialize(); telnet_done = true; }
  if (!ota_done) { networking::ota::initialize(); ota_done = true; }
}

//------------------------------------------
//  System Task
//------------------------------------------
static void system_task(void *pvParameters) {
  (void)pvParameters;

  Serial.println(F("[system] booting..."));

  LED.init();
  LED.set(RGB_YELLOW);

  // Power on I2C sensor relay and init buses
  hardware::i2c::enable();
  delay(100);
  Wire.begin(config::i2c::BUS_0.sda_gpio, config::i2c::BUS_0.scl_gpio, config::i2c::FREQUENCY_KHZ * 1000);
  Wire.setTimeOut(100);
  Wire1.begin(config::i2c::BUS_1.sda_gpio, config::i2c::BUS_1.scl_gpio, config::i2c::FREQUENCY_KHZ * 1000);
  Wire1.setTimeOut(100);

  // Discover sensors behind TCA9548A mux
  hardware::i2c::initialize();
  sensors::temperature_and_humidity::discover();
  sensors::voltage::initialize();
  sensors::carbon_dioxide::initialize();

#if CERATINA_BLE_ENABLED
  networking::ble::initialize();
#endif

  programs::shell::initialize();
  programs::buttons::initialize();

  if (!LittleFS.begin(false)) {
    Serial.println(F("[fs] mount failed, formatting..."));
    LED.set(255, 100, 0);
    if (!LittleFS.begin(true)) {
      Serial.println(F("[fs] format failed — filesystem unavailable"));
    }
  }
  if (LittleFS.totalBytes() > 0) {
    Serial.printf("[fs] LittleFS: %u/%u KB used\n",
                  (unsigned)(LittleFS.usedBytes() / 1024),
                  (unsigned)(LittleFS.totalBytes() / 1024));
    LED.set(RGB_YELLOW);
  }

  // Check for firmware update on SD card before WiFi
  networking::update::checkSDOnBoot();

#if CERATINA_PROV_ENABLED
  if (!networking::provisioning::isProvisioned()) {
    Serial.println(F("[prov] not provisioned — starting BLE provisioning"));
    LED.set(RGB_MAGENTA);
    networking::provisioning::start();
  }
#endif

  if (networking::wifi::sta::connect()) {
    LED.set(RGB_GREEN);
    Serial.printf("[wifi] connected, heap: %u bytes free\n", ESP.getFreeHeap());
  } else {
    Serial.println(F("[wifi] STA not connected — starting AP for provisioning"));
    networking::wifi::ap::enable();
    LED.set(255, 100, 0);
  }

  network_services_start();

  // Shell service loop (non-blocking) + SSE heartbeat + DNS
  uint32_t last_heartbeat = 0;

  for (;;) {
    services::http::service();
    programs::shell::service();
    services::ws_shell::service();
    networking::telnet::service();
    networking::ota::service();
    programs::buttons::service();

#if CERATINA_BLE_ENABLED
    networking::ble::service();
#endif

    if (millis() - last_heartbeat > 5000) {
      last_heartbeat = millis();
      uint32_t heap = ESP.getFreeHeap();
      char buf[64];
      snprintf(buf, sizeof(buf), "{\"uptime\":%lu,\"heap\":%u}",
               millis() / 1000, heap);
      http_events.send(buf, "heartbeat", millis());

      if (heap < 20000) {
        Serial.printf("[WARN] low heap: %u bytes free (min: %u)\n",
                      heap, ESP.getMinFreeHeap());
      }
    }

    vTaskDelay(pdMS_TO_TICKS(config::system::SHELL_SERVICE_MS));
  }
}

//------------------------------------------
//  Arduino Entry Points
//------------------------------------------
#ifndef PIO_UNIT_TESTING

void setup(void) {
  Serial.begin(config::system::SERIAL_BAUD);
  delay(100);

  networking::wifi::sta::initialize();

  xTaskCreatePinnedToCore(system_task, "system", config::system::TASK_STACK, NULL,
                          1, NULL, 1);
}

void loop(void) {}

#endif
