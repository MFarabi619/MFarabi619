#ifdef PIO_UNIT_TESTING

#include "telnet.h"
#include "wifi.h"
#include "../testing/it.h"

#include <Arduino.h>
#include <WiFi.h>

static void telnet_test_config(void) {
  TEST_MESSAGE("user verifies telnet configuration");

#if CONFIG_TELNET_ENABLED
  TEST_ASSERT_GREATER_THAN_UINT16_MESSAGE(0, CONFIG_TELNET_PORT,
    "device: telnet port must be > 0");
  TEST_ASSERT_GREATER_THAN_UINT16_MESSAGE(0, CONFIG_TELNET_RING_SIZE,
    "device: ring buffer must be > 0");
  TEST_ASSERT_GREATER_THAN_UINT16_MESSAGE(0, CONFIG_TELNET_WRITE_BUF,
    "device: write buffer must be > 0");

  char msg[64];
  snprintf(msg, sizeof(msg), "telnet enabled on port %d", CONFIG_TELNET_PORT);
  TEST_MESSAGE(msg);
#else
  TEST_IGNORE_MESSAGE("telnet not enabled");
#endif
}

static void telnet_test_not_connected_before_start(void) {
  TEST_MESSAGE("user verifies telnet reports no client before any connection");

#if CONFIG_TELNET_ENABLED
  TEST_ASSERT_FALSE_MESSAGE(telnet_is_connected(),
    "device: should not be connected before any client joins");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("", telnet_client_ip(),
    "device: client IP should be empty when no client");
#else
  TEST_IGNORE_MESSAGE("telnet not enabled");
#endif
}

static void telnet_test_starts_when_wifi_connected(void) {
  TEST_MESSAGE("user verifies telnet starts after WiFi");

#if CONFIG_TELNET_ENABLED
  wifi_setup();
  if (!wifi_connect()) {
    TEST_IGNORE_MESSAGE("skipped — no WiFi connection");
    return;
  }

  telnet_start();
  telnet_service();

  TEST_ASSERT_FALSE_MESSAGE(telnet_is_connected(),
    "device: should not report connected with no client");

  char msg[80];
  snprintf(msg, sizeof(msg), "telnet listening — connect with: telnet %s",
           WiFi.localIP().toString().c_str());
  TEST_MESSAGE(msg);
#else
  TEST_IGNORE_MESSAGE("telnet not enabled");
#endif
}

static void telnet_test_disconnect_is_safe_when_idle(void) {
  TEST_MESSAGE("user verifies disconnect is a no-op when no client");

#if CONFIG_TELNET_ENABLED
  telnet_disconnect();
  TEST_ASSERT_FALSE_MESSAGE(telnet_is_connected(),
    "device: still reports disconnected after no-op disconnect");
#else
  TEST_IGNORE_MESSAGE("telnet not enabled");
#endif
}

void telnet_run_tests(void) {
  it("user observes that telnet config is valid",
     telnet_test_config);
  it("user observes that telnet reports no client before start",
     telnet_test_not_connected_before_start);
  it("user observes that telnet starts when WiFi is connected",
     telnet_test_starts_when_wifi_connected);
  it("user observes that telnet disconnect is safe when idle",
     telnet_test_disconnect_is_safe_when_idle);
}

#endif
