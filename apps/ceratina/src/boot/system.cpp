#include <boot/system.h>

#include <config.h>
#include "provisioning.h"
#include <i2c.h>
#include <storage.h>
#include <networking/wifi.h>
#include "../networking/sntp.h"
#include "../networking/telnet.h"
#include "../networking/ota.h"
#include "../networking/update.h"
#include "../networking/ble.h"
#include "../networking/tunnel.h"
#include "../programs/buttons.h"
#include <led.h>
#include "../power/sleep.h"
#include "../power/sleep_after_poll.h"
#include "../programs/shell/shell.h"
#include "../programs/ssh/ssh_server.h"
#include "../services/http.h"
#include "../services/data_logger.h"
#include "../services/ws_shell.h"
#include <identity.h>
#include <manager.h>

#include <hal.h>
#include <freertos/timers.h>
#include <Wire.h>

namespace {

void initialize_hardware(void) {
  Serial.println(F("[system] booting..."));

  LED.init();
  LED.fadeIn(colors::Gold, 600);

  hardware::i2c::initialize();
  hardware::storage::initialize();
  power::sleep::initialize();
  services::identity::initialize();
}

void initialize_services_and_programs(void) {
  sensors::manager::initialize();

#if CERATINA_BLE_ENABLED
  networking::ble::initialize();
#endif

  programs::shell::initialize();
  // programs::buttons::initialize();
  // programs::buttons::onLongPressStart([](uint8_t index) {
  //   Serial.printf("[buttons] long press on GPIO %d — requesting sleep\n", index);
  //   SleepCommand command = {};
  //   power::sleep::requestConfigured(&command);
  // });
  services::data_logger::initialize();
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
      LED.set(colors::Yellow);
    }
  }
}

void run_provisioning_policy(void) {
  networking::update::checkSDOnBoot();

  if (boot::provisioning::isEnabled() && !boot::provisioning::isProvisioned()) {
    Serial.println(F("[prov] not provisioned — starting BLE provisioning"));
    LED.set(colors::Magenta);
    boot::provisioning::start();
  }
}

void connect_networking(void) {
  networking::wifi::ap::enable();

  if (networking::wifi::sta::connect()) {
    LED.set(colors::Green);
    Serial.printf("[wifi] connected, heap: %u bytes free\n", hal::system::freeHeap());
  } else {
    Serial.println(F("[wifi] STA not connected — AP remains active for provisioning"));
    LED.set(colors::DarkOrange);
  }
}

void heartbeat_callback(TimerHandle_t) {
  uint32_t heap = hal::system::freeHeap();
  char buf[64];
  snprintf(buf, sizeof(buf), "{\"uptime\":%lu,\"heap\":%u}",
           hal::system::uptimeSeconds(), heap);
  services::http::emitEvent(buf, "heartbeat", hal::system::uptimeMilliseconds());

  if (heap < 20000) {
    Serial.printf("[WARN] low heap: %u bytes free (min: %u)\n",
                  heap, hal::system::minFreeHeap());
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

#if CERATINA_SLEEP_AFTER_POLL_ENABLED
  power::sleep_after_poll::initialize();
#endif

  TimerHandle_t heartbeat = xTimerCreate("heartbeat", pdMS_TO_TICKS(5000),
                                          pdTRUE, nullptr, heartbeat_callback);
  xTimerStart(heartbeat, 0);

  for (;;) {
    services::http::service();
    programs::shell::service();
    services::ws_shell::service();
    networking::telnet::service();
    networking::ota::service();
    // programs::buttons::service();
    power::sleep::service();

#if CERATINA_SLEEP_AFTER_POLL_ENABLED
    power::sleep_after_poll::service();
#endif

#if CERATINA_BLE_ENABLED
    networking::ble::service();
#endif

#if CERATINA_TUNNEL_ENABLED
    networking::tunnel::service();
#endif

    vTaskDelay(pdMS_TO_TICKS(config::system::SHELL_SERVICE_MS));
  }
}

}

void boot::system::startServices() {
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

  static bool tunnel_done = false;
  if (!tunnel_done) { networking::tunnel::initialize(); tunnel_done = true; }
}

void boot::system::startTask() {
  xTaskCreatePinnedToCore(system_task, "system", config::system::TASK_STACK,
                          nullptr, 1, nullptr, 1);
}
