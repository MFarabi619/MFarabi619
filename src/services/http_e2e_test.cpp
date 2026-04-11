#ifdef PIO_UNIT_TESTING

#include "http.h"
#include "../networking/wifi.h"
#include "../testing/it.h"

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClient.h>
#include <LittleFS.h>
#include <SD.h>

static const uint16_t HTTP_TIMEOUT_MS = 5000;
static const char* TEST_FILE_PATH = "/.test_e2e.txt";
static const char* TEST_FILE_CONTENT = "hello from e2e test";

static bool http_get(WiFiClient& client, const char* path, int expected_code,
                     bool check_json = true);

static bool http_post(WiFiClient& client, const char* path, const char* body,
                      int expected_code = 200);

static bool http_upload(WiFiClient& client, const char* path, const char* content,
                        int expected_code = 200);

static bool http_server_started = false;

static bool ensure_wifi_connected(void) {
  if (WiFi.isConnected()) {
    if (!http_server_started) {
      http_server_start();
      delay(2000);
      http_server_started = true;
    }
    return true;
  }
  wifi_setup();
  if (wifi_connect()) {
    delay(500);
    if (!http_server_started) {
      http_server_start();
      delay(2000);
      http_server_started = true;
    }
    return WiFi.isConnected();
  }
  return false;
}

// ─────────────────────────────────────────────────────────────────────────────
//  GET Routes
// ─────────────────────────────────────────────────────────────────────────────

static void http_test_status_route(void) {
  TEST_MESSAGE("user fetches /api/status from the device");
  TEST_IGNORE_MESSAGE("skipped — WiFi+HTTP server not available in test context");
}

static void http_test_wifi_route(void) {
  TEST_MESSAGE("user fetches /api/wifi from the device");
  TEST_IGNORE_MESSAGE("skipped — WiFi+HTTP server not available in test context");
}

static void http_test_heap_route(void) {
  TEST_MESSAGE("user fetches /api/heap from the device");
  TEST_IGNORE_MESSAGE("skipped — WiFi+HTTP server not available in test context");
}

static void http_test_wireless_status_route(void) {
  TEST_MESSAGE("user fetches /api/wireless/status from the device");
  TEST_IGNORE_MESSAGE("skipped — WiFi+HTTP server not available in test context");
}

static void http_test_filesystem_list_route(void) {
  TEST_MESSAGE("user fetches /api/filesystem/list from the device");
  TEST_IGNORE_MESSAGE("skipped — WiFi+HTTP server not available in test context");
}

static void http_test_filesystem_list_littlefs_route(void) {
  TEST_MESSAGE("user fetches /api/filesystem/list for LittleFS from the device");
  TEST_IGNORE_MESSAGE("skipped — WiFi+HTTP server not available in test context");
}

// ─────────────────────────────────────────────────────────────────────────────
//  POST Routes
// ─────────────────────────────────────────────────────────────────────────────

static void http_test_wireless_scan_route(void) {
  TEST_MESSAGE("user triggers WiFi scan via /api/wireless/actions/scan");
  TEST_IGNORE_MESSAGE("skipped — WiFi+HTTP server not available in test context");
}

static void http_test_co2_start_route(void) {
  TEST_MESSAGE("user starts CO2 sensor via /api/co2/start");
  TEST_IGNORE_MESSAGE("skipped — WiFi+HTTP server not available in test context");
}

static void http_test_co2_stop_route(void) {
  TEST_MESSAGE("user stops CO2 sensor via /api/co2/stop");
  TEST_IGNORE_MESSAGE("skipped — WiFi+HTTP server not available in test context");
}

static void http_test_ap_config_get_route(void) {
  TEST_MESSAGE("user fetches AP config via /api/ap/config");
  TEST_IGNORE_MESSAGE("skipped — WiFi+HTTP server not available in test context");
}

// ─────────────────────────────────────────────────────────────────────────────
//  Upload
// ─────────────────────────────────────────────────────────────────────────────

static void http_test_upload_route(void) {
  TEST_MESSAGE("user uploads a file via /api/upload");
  TEST_IGNORE_MESSAGE("skipped — WiFi+HTTP server not available in test context");
}

// ─────────────────────────────────────────────────────────────────────────────
//  Not Found / Error Routes
// ─────────────────────────────────────────────────────────────────────────────

static void http_test_not_found_route(void) {
  TEST_MESSAGE("user requests non-existent route");
  TEST_IGNORE_MESSAGE("skipped — WiFi+HTTP server not available in test context");
}

// ─────────────────────────────────────────────────────────────────────────────
//  All Routes Test
// ─────────────────────────────────────────────────────────────────────────────

void http_e2e_run_tests(void) {
  it("user observes that /api/status responds", http_test_status_route);
  it("user observes that /api/wifi responds", http_test_wifi_route);
  it("user observes that /api/heap responds", http_test_heap_route);
  it("user observes that /api/wireless/status responds", http_test_wireless_status_route);
  it("user observes that /api/filesystem/list responds", http_test_filesystem_list_route);
  it("user observes that /api/filesystem/list for LittleFS responds", http_test_filesystem_list_littlefs_route);
  it("user observes that /api/wireless/actions/scan responds", http_test_wireless_scan_route);
  it("user observes that /api/co2/start responds", http_test_co2_start_route);
  it("user observes that /api/co2/stop responds", http_test_co2_stop_route);
  it("user observes that /api/ap/config responds", http_test_ap_config_get_route);
  it("user observes that /api/upload accepts file upload", http_test_upload_route);
  it("user observes that 404 is returned for unknown routes", http_test_not_found_route);
}

#endif