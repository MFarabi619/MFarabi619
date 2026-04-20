#pragma once

#include "services/data_logger.h"
#include <identity.h>
#include <storage.h>
#include <networking/wifi.h>
#include "power/sleep.h"

#include <stddef.h>
#include <stdint.h>

struct SystemSnapshot {
  DeviceIdentitySnapshot identity;
  NetworkStatusSnapshot network;
  StorageSnapshot storage;
  uint32_t uptime_seconds;
  uint32_t heap_free;
  uint32_t heap_total;
  uint32_t heap_min_free;
  uint32_t heap_max_alloc;
  uint32_t psram_total;
  uint32_t psram_free;
  char chip_model[32];
  uint32_t chip_cores;
  uint32_t chip_revision;
  uint32_t cpu_mhz;
  uint32_t flash_size;
  uint32_t flash_speed_mhz;
  uint32_t sketch_size;
  uint32_t sketch_free;
  float chip_temperature_celsius;
  char sdk_version[32];
  char idf_version[32];
  char arduino_version[32];
  char sketch_md5[40];
  SleepStatusSnapshot sleep;
  DataLoggerStatusSnapshot data_logger;
};

struct SystemQuery {
  StorageKind preferred_storage;
  SystemSnapshot snapshot;
};

namespace services::system {

bool accessSnapshot(SystemQuery *query);
size_t formatUptime(char *buf, size_t len, uint32_t uptime_seconds);

}

