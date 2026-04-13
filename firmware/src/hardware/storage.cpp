#include "storage.h"

#include <Arduino.h>
#include <LittleFS.h>
#include <SD.h>

namespace {

bool littlefs_attempted = false;
bool littlefs_ready = false;
bool sd_attempted = false;
bool sd_ready = false;

}

void hardware::storage::initialize() {
  littlefs_attempted = false;
  littlefs_ready = false;
  sd_attempted = false;
  sd_ready = false;
}

bool hardware::storage::ensureLittleFS() {
  if (littlefs_attempted) return littlefs_ready;
  littlefs_attempted = true;

  littlefs_ready = LittleFS.begin(false);
  if (!littlefs_ready) {
    Serial.println(F("[fs] mount failed, formatting..."));
    littlefs_ready = LittleFS.begin(true);
    if (!littlefs_ready) {
      Serial.println(F("[fs] format failed — filesystem unavailable"));
    }
  }
  return littlefs_ready;
}

bool hardware::storage::ensureSD() {
  if (sd_attempted) return sd_ready;
  sd_attempted = true;

  sd_ready = SD.begin(SS, SPI, 4000000, "/sd", 5, false);
  if (!sd_ready) {
    Serial.println(F("[sd] no FAT volume — formatting..."));
    sd_ready = SD.begin(SS, SPI, 4000000, "/sd", 5, true);
    if (!sd_ready) {
      Serial.println(F("[sd] format failed — SD unavailable"));
    }
  }
  return sd_ready;
}

bool hardware::storage::isLittleFSReady() {
  return littlefs_ready;
}

bool hardware::storage::isSDReady() {
  return sd_ready;
}

bool hardware::storage::accessSnapshot(StorageQuery *query) {
  if (!query) return false;
  query->snapshot.kind = query->kind;
  query->snapshot.mounted = false;
  query->snapshot.total_bytes = 0;
  query->snapshot.used_bytes = 0;
  query->snapshot.free_bytes = 0;

  if (query->kind == StorageKind::LittleFS) {
    if (!hardware::storage::ensureLittleFS()) return false;
    query->snapshot.mounted = true;
    query->snapshot.total_bytes = LittleFS.totalBytes();
    query->snapshot.used_bytes = LittleFS.usedBytes();
    query->snapshot.free_bytes = query->snapshot.total_bytes - query->snapshot.used_bytes;
    return true;
  }

  if (!hardware::storage::ensureSD()) return false;
  query->snapshot.mounted = true;
  query->snapshot.total_bytes = SD.totalBytes();
  query->snapshot.used_bytes = SD.usedBytes();
  query->snapshot.free_bytes = query->snapshot.total_bytes - query->snapshot.used_bytes;
  return true;
}
