#ifndef HARDWARE_STORAGE_H
#define HARDWARE_STORAGE_H

#include <stdint.h>

enum class StorageKind { LittleFS, SD };

struct StorageSnapshot {
  bool mounted;
  StorageKind kind;
  uint64_t total_bytes;
  uint64_t used_bytes;
  uint64_t free_bytes;
};

struct StorageQuery {
  StorageKind kind;
  StorageSnapshot snapshot;
};

namespace hardware::storage {

void initialize();
bool ensureLittleFS();
bool ensureSD();
bool isLittleFSReady();
bool isSDReady();
bool accessSnapshot(StorageQuery *query);

}

#endif
