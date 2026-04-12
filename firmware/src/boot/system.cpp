#include "system.h"

#include "../config.h"
#include "provisioning.h"
#include "../hardware/i2c.h"
#include "../hardware/storage.h"
#include "../networking/wifi.h"
#include "../networking/sntp.h"
#include "../networking/telnet.h"
#include "../networking/ota.h"
#include "../networking/update.h"
#include "../networking/ble.h"
#include "../programs/buttons.h"
#include "../programs/led.h"
#include "../programs/shell/shell.h"
#include "../programs/ssh/ssh_server.h"
#include "../services/http.h"
#include "../services/ws_shell.h"
#include "../services/identity.h"
#include "../sensors/manager.h"

#include <Arduino.h>
#include <ColorFormat.h>
#include <Wire.h>

namespace {

void initialize_hardware(void) {
  Serial.println(F("[system] booting..."));

  LED.init();
  LED.set(RGB_YELLOW);

  hardware::i2c::enable();
  delay(100);
  hardware::i2c::initialize();
  hardware::storage::initialize();
  services::identity::initialize();
}

void initialize_services_and_programs(void) {
  sensors::manager::initialize();

#if CERATINA_BLE_ENABLED
  networking::ble::initialize();
#endif

  programs::shell::initialize();
  programs::buttons::initialize();
}

void initialize_storage(void) {
  if (hardware::storage::ensureLittleFS()) {
    StorageQuery query = {
      .kind = StorageKind::LittleFS,
      .snapshot = {},
    };
    if (hardware::storage::accessSnapshot(&query)) {
      Serial.printf("[fs] LittleFS: %u/%u KB used\n",
                    (unsigned)(query.snapshot.used_bytes / 1024),
                    (unsigned)(query.snapshot.total_bytes / 1024));
      LED.set(RGB_YELLOW);
    }
  }
}

void run_provisioning_policy(void) {
  networking::update::checkSDOnBoot();

  if (boot::provisioning::isEnabled() && !boot::provisioning::isProvisioned()) {
    Serial.println(F("[prov] not provisioned — starting BLE provisioning"));
    LED.set(RGB_MAGENTA);
    boot::provisioning::start();
  }
}

void connect_networking(void) {
  if (networking::wifi::sta::connect()) {
    LED.set(RGB_GREEN);
    Serial.printf("[wifi] connected, heap: %u bytes free\n", ESP.getFreeHeap());
  } else {
    Serial.println(F("[wifi] STA not connected — starting AP for provisioning"));
    networking::wifi::ap::enable();
    LED.set(255, 100, 0);
  }
}

void system_task(void *pvParameters) {
  (void)pvParameters;

  initialize_hardware();
  initialize_services_and_programs();
  initialize_storage();
  run_provisioning_policy();
  connect_networking();
  boot::system::startServices();

  uint32_t last_heartbeat = 0;
  for (;;) {
    services::http::service();
    programs::shell::service();
    services::ws_shell::service();
    networking::telnet::service();
    networking::ota::service();
    programs::buttons::service();
    sensors::manager::service();

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

}

void boot::system::startServices() noexcept {
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

void boot::system::startTask() noexcept {
  xTaskCreatePinnedToCore(system_task, "system", config::system::TASK_STACK,
                          nullptr, 1, nullptr, 1);
}
