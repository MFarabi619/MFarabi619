#include "update.h"
#include <storage.h>
#include <led.h>

#include <Arduino.h>
#include <Update.h>
#include <SD.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <HTTPUpdate.h>

static void log_progress(size_t current, size_t total) {
  if (total == 0) return;
  Serial.printf("[update] %u%%\r", (unsigned)(current * 100 / total));
}

bool networking::update::applyFromSD(const char *path) {
  if (!hardware::storage::ensureSD()) {
    Serial.println(F("[update] SD card not available"));
    return false;
  }

  if (!SD.exists(path)) return false;

  File bin = SD.open(path, FILE_READ);
  if (!bin || bin.isDirectory()) {
    Serial.println(F("[update] cannot open update file"));
    if (bin) bin.close();
    return false;
  }

  size_t size = bin.size();
  if (size == 0) {
    Serial.println(F("[update] update file is empty"));
    bin.close();
    return false;
  }

  Serial.printf("[update] found %s (%u bytes)\n", path, (unsigned)size);
  LED.set(colors::Magenta);

  String md5_path = String(path) + ".md5";
  if (SD.exists(md5_path)) {
    File md5_file = SD.open(md5_path, FILE_READ);
    if (md5_file) {
      String md5 = md5_file.readStringUntil('\n');
      md5.trim();
      md5_file.close();
      if (md5.length() == 32) {
        Update.setMD5(md5.c_str());
        Serial.printf("[update] MD5: %s\n", md5.c_str());
      }
    }
  }

  Update.onProgress(log_progress);

  if (!Update.begin(size, U_FLASH)) {
    Serial.printf("[update] begin failed: %s\n", Update.errorString());
    bin.close();
    return false;
  }

  size_t written = Update.writeStream(bin);
  bin.close();

  if (written != size) {
    Serial.printf("[update] wrote %u/%u bytes\n", (unsigned)written, (unsigned)size);
    Update.abort();
    return false;
  }

  if (!Update.end()) {
    Serial.printf("[update] verify failed: %s\n", Update.errorString());
    return false;
  }

  Serial.println(F("[update] SD update successful, removing file"));
  SD.remove(path);
  if (SD.exists(md5_path)) SD.remove(md5_path);
  return true;
}

bool networking::update::applyFromURL(const char *url, const char *cert_pem) {
  if (!url || url[0] == '\0') {
    Serial.println(F("[update] no URL provided"));
    return false;
  }

  Serial.printf("[update] fetching %s\n", url);
  LED.set(colors::Magenta);

  WiFiClientSecure client;
  if (cert_pem) {
    client.setCACert(cert_pem);
  } else {
    client.setInsecure();
  }

  httpUpdate.rebootOnUpdate(false);
  httpUpdate.setFollowRedirects(HTTPC_FORCE_FOLLOW_REDIRECTS);

  httpUpdate.onStart([]() {
    Serial.println(F("[update] download started"));
  });
  httpUpdate.onEnd([]() {
    Serial.println(F("[update] download complete"));
  });
  httpUpdate.onProgress([](int current, int total) {
    if (total > 0)
      Serial.printf("[update] %d%%\r", current * 100 / total);
  });
  httpUpdate.onError([](int error) {
    Serial.printf("[update] HTTP error: %d\n", error);
  });

  t_httpUpdate_return result = httpUpdate.update(client, url);

  switch (result) {
    case HTTP_UPDATE_OK:
      Serial.println(F("[update] HTTPS update successful"));
      return true;
    case HTTP_UPDATE_NO_UPDATES:
      Serial.println(F("[update] server reports no update available"));
      return false;
    case HTTP_UPDATE_FAILED:
    default:
      Serial.printf("[update] failed: %s\n",
                    httpUpdate.getLastErrorString().c_str());
      return false;
  }
}

bool networking::update::canRollback() {
  return Update.canRollBack();
}

bool networking::update::rollback() {
  if (!Update.canRollBack()) {
    Serial.println(F("[update] no rollback partition available"));
    return false;
  }
  Serial.println(F("[update] rolling back to previous firmware"));
  return Update.rollBack();
}

void networking::update::checkSDOnBoot() {
  if (networking::update::applyFromSD()) {
    Serial.println(F("[update] rebooting into new firmware..."));
    delay(500);
    ESP.restart();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING

#include "update.h"
#include <testing/utils.h>

namespace networking::update { void test(void); }

static void test_update_sd_path_config(void) {
  THEN("the SD update path is configured");
  TEST_ASSERT_NOT_NULL(config::ota::SD_PATH);
  TEST_ASSERT_NOT_EMPTY_MESSAGE(config::ota::SD_PATH,
    "device: config::ota::SD_PATH must not be empty");

  TEST_PRINTF("SD update file: %s", config::ota::SD_PATH);
}

static void test_update_no_update_file(void) {
  WHEN("applyFromSD is called with no update file");
  THEN("it returns false");

  if (!hardware::storage::ensureSD()) {
    TEST_IGNORE_MESSAGE("skipped — no SD card");
    return;
  }

  if (SD.exists(config::ota::SD_PATH)) {
    TEST_IGNORE_MESSAGE("skipped — update.bin exists on SD (would flash!)");
    return;
  }

  TEST_ASSERT_FALSE_MESSAGE(networking::update::applyFromSD(),
    "device: should return false when no update file");
}

static void test_update_rollback_status(void) {
  WHEN("rollback availability is checked");

  bool can = networking::update::canRollback();
  TEST_PRINTF("rollback available: %s", can ? "yes" : "no");
}

void networking::update::test(void) {
  MODULE("Update");
  RUN_TEST(test_update_sd_path_config);
  RUN_TEST(test_update_no_update_file);
  RUN_TEST(test_update_rollback_status);
}

#endif
