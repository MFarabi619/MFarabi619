#include "ota.h"

#if CERATINA_OTA_ENABLED

#include <Arduino.h>
#include <ArduinoOTA.h>
#include <WiFi.h>

static bool started = false;
static bool updating = false;

void networking::ota::initialize(void) {
  if (started) return;

  ArduinoOTA.setHostname(config::HOSTNAME);
  ArduinoOTA.setPort(config::ota::PORT);

  if (config::ota::PASSWORD[0] != '\0')
    ArduinoOTA.setPassword(config::ota::PASSWORD);

  ArduinoOTA
    .onStart([]() {
      updating = true;
      const char *type = (ArduinoOTA.getCommand() == U_FLASH)
          ? "firmware" : "filesystem";
      Serial.printf("[ota] start updating %s\n", type);
    })
    .onEnd([]() {
      updating = false;
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
  Serial.printf("[ota] listening on port %d\n", config::ota::PORT);
}

void networking::ota::service(void) {
  if (!started) return;
  ArduinoOTA.handle();
}

bool networking::ota::isInProgress(void) {
  return updating;
}

#else

void networking::ota::initialize(void) {}
void networking::ota::service(void) {}
bool networking::ota::isInProgress(void) { return false; }

#endif

// ─────────────────────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING


#include "ota.h"
#include <testing/utils.h>

namespace networking::ota { void test(void); }

#include <Arduino.h>

static void ota_test_config(void) {
  TEST_MESSAGE("user verifies OTA configuration");

  TEST_ASSERT_GREATER_THAN_UINT16_MESSAGE(0, config::ota::PORT,
    "device: OTA port must be > 0");

#if CERATINA_OTA_ENABLED
  char msg[64];
  snprintf(msg, sizeof(msg), "OTA enabled on port %d", config::ota::PORT);
  TEST_MESSAGE(msg);
#else
  TEST_MESSAGE("OTA is disabled (CERATINA_OTA_ENABLED=0)");

#endif
}

static void ota_test_noop_when_disabled(void) {
  TEST_MESSAGE("user calls OTA functions when disabled");
#if !CERATINA_OTA_ENABLED
  networking::ota::initialize();
  networking::ota::service();
  TEST_MESSAGE("no-ops completed without error");
#else
  TEST_IGNORE_MESSAGE("OTA is enabled — test not applicable");
#endif
}

void networking::ota::test(void) {
  it("user verifies OTA configuration",
     ota_test_config);
  it("user verifies OTA no-ops when disabled",
     ota_test_noop_when_disabled);
}

#endif
