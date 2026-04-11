#include "ota.h"

#if CONFIG_OTA_ENABLED

#include <Arduino.h>
#include <ArduinoOTA.h>
#include <WiFi.h>

static bool started = false;

void ota_start(void) {
  if (started) return;

  ArduinoOTA.setHostname(CONFIG_HOSTNAME);
  ArduinoOTA.setPort(CONFIG_OTA_PORT);

#if defined(CONFIG_OTA_PASSWORD) && CONFIG_OTA_PASSWORD[0] != '\0'
  ArduinoOTA.setPassword(CONFIG_OTA_PASSWORD);
#endif

  ArduinoOTA
    .onStart([]() {
      const char *type = (ArduinoOTA.getCommand() == U_FLASH)
          ? "firmware" : "filesystem";
      Serial.printf("[ota] start updating %s\n", type);
    })
    .onEnd([]() {
      Serial.println(F("\n[ota] update complete"));
    })
    .onProgress([](unsigned int progress, unsigned int total) {
      Serial.printf("[ota] %u%%\r", progress / (total / 100));
    })
    .onError([](ota_error_t error) {
      const char *msg = "unknown";
      switch (error) {
        case OTA_AUTH_ERROR:    msg = "auth failed"; break;
        case OTA_BEGIN_ERROR:   msg = "begin failed"; break;
        case OTA_CONNECT_ERROR: msg = "connect failed"; break;
        case OTA_RECEIVE_ERROR: msg = "receive failed"; break;
        case OTA_END_ERROR:     msg = "end failed"; break;
      }
      Serial.printf("[ota] error: %s\n", msg);
    });

  ArduinoOTA.begin();
  started = true;
  Serial.printf("[ota] listening on port %d\n", CONFIG_OTA_PORT);
}

void ota_service(void) {
  if (!started) return;
  ArduinoOTA.handle();
}

#else

void ota_start(void) {}
void ota_service(void) {}

#endif
