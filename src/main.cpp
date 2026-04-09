//------------------------------------------
//  Includes
//------------------------------------------
#include <Arduino.h>
#include <LittleFS.h>
#include <WiFi.h>

#include "esp_netif.h"
#include "programs/ssh/ssh_server.h"
#include "programs/shell/shell.h"

//------------------------------------------
//  Configuration
//------------------------------------------
static const char *WIFI_SSID = "YOUR_SSID";
static const char *WIFI_PASSWORD = "YOUR_PASSWORD";

static const uint32_t SYSTEM_TASK_STACK_SIZE = 8192;
static const uint32_t WIFI_TIMEOUT_MS = 15000;
static const uint32_t WIFI_POLL_INTERVAL_MS = 100;

//------------------------------------------
//  Globals
//------------------------------------------
static volatile bool wifi_connected = false;

//------------------------------------------
//  WiFi
//------------------------------------------
static void wifi_event_handler(void *arg, esp_event_base_t base, int32_t id,
                               void *event_data) {
  switch (id) {
  case WIFI_EVENT_STA_CONNECTED:
    Serial.println("[wifi] connected");
    break;
  case WIFI_EVENT_STA_DISCONNECTED:
    Serial.println("[wifi] disconnected, reconnecting...");
    wifi_connected = false;
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    break;
  case IP_EVENT_STA_GOT_IP: {
    ip_event_got_ip_t *event = (ip_event_got_ip_t *)event_data;
    Serial.printf("[wifi] got ip: %s\n",
                  IPAddress(event->ip_info.ip.addr).toString().c_str());
    wifi_connected = true;
  } break;
  default:
    break;
  }
}

static bool wifi_init(void) {
  WiFi.disconnect(true);
  WiFi.mode(WIFI_MODE_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  uint32_t start = millis();
  while (!wifi_connected && (millis() - start) < WIFI_TIMEOUT_MS) {
    vTaskDelay(pdMS_TO_TICKS(WIFI_POLL_INTERVAL_MS));
  }
  return wifi_connected;
}

//------------------------------------------
//  System Task
//------------------------------------------
static void system_task(void *pvParameters) {
  (void)pvParameters;

  Serial.println("[system] booting...");

  // Initialize shell (Serial console available immediately)
  shell_init();

  // Mount LittleFS for SSH host key storage
  if (!LittleFS.begin(true)) {
    Serial.println("[fs] LittleFS mount failed");
  } else {
    Serial.printf("[fs] LittleFS mounted, used=%d total=%d\n",
                  LittleFS.usedBytes(), LittleFS.totalBytes());

    // Ensure .ssh directory exists
    if (!LittleFS.exists("/.ssh")) {
      LittleFS.mkdir("/.ssh");
      Serial.println("[fs] created /.ssh directory");
    }
  }

  // Connect WiFi
  if (!wifi_init()) {
    Serial.println("[wifi] connection failed, rebooting in 10s...");
    vTaskDelay(pdMS_TO_TICKS(10000));
    esp_restart();
  }

  // Start services
  ssh_server_start();

  // Shell service loop (non-blocking)
  for (;;) {
    shell_service();
    vTaskDelay(pdMS_TO_TICKS(10));
  }
}

//------------------------------------------
//  Arduino Entry Points
//------------------------------------------
#ifndef PIO_UNIT_TESTING

void setup(void) {
  Serial.begin(115200);
  delay(100);

  esp_netif_init();
  esp_event_loop_create_default();
  esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID,
                                      wifi_event_handler, NULL, NULL);
  esp_event_handler_instance_register(IP_EVENT, ESP_EVENT_ANY_ID,
                                      wifi_event_handler, NULL, NULL);

  xTaskCreatePinnedToCore(system_task, "system", SYSTEM_TASK_STACK_SIZE, NULL,
                          1, NULL, 1);
}

void loop(void) {}

#endif
