#include "update.h"

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

bool update_from_sd(const char *path) {
  if (!SD.begin(CONFIG_SD_CS_GPIO)) {
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

  // Check for companion .md5 file
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

bool update_from_url(const char *url, const char *cert_pem) {
  if (!url || url[0] == '\0') {
    Serial.println(F("[update] no URL provided"));
    return false;
  }

  Serial.printf("[update] fetching %s\n", url);

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

bool update_can_rollback(void) {
  return Update.canRollBack();
}

bool update_rollback(void) {
  if (!Update.canRollBack()) {
    Serial.println(F("[update] no rollback partition available"));
    return false;
  }
  Serial.println(F("[update] rolling back to previous firmware"));
  return Update.rollBack();
}

void update_check_sd_on_boot(void) {
  if (update_from_sd()) {
    Serial.println(F("[update] rebooting into new firmware..."));
    delay(500);
    ESP.restart();
  }
}
