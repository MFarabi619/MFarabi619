#include <services/system.h>

#include <Arduino.h>
#include <string.h>

size_t services::system::formatUptime(char *buf, size_t len, uint32_t uptime_seconds) {
  if (!buf || len == 0) return 0;

  uint32_t days = uptime_seconds / 86400;
  uint32_t hours = (uptime_seconds % 86400) / 3600;
  uint32_t minutes = (uptime_seconds % 3600) / 60;
  uint32_t seconds = uptime_seconds % 60;

  if (days > 0) {
    return snprintf(buf, len, "%lud %luh %lum %lus",
                    (unsigned long)days, (unsigned long)hours,
                    (unsigned long)minutes, (unsigned long)seconds);
  }
  if (hours > 0) {
    return snprintf(buf, len, "%luh %lum %lus",
                    (unsigned long)hours, (unsigned long)minutes,
                    (unsigned long)seconds);
  }
  return snprintf(buf, len, "%lum %lus",
                  (unsigned long)minutes, (unsigned long)seconds);
}

bool services::system::accessSnapshot(SystemQuery *query) {
  if (!query) return false;
  memset(&query->snapshot, 0, sizeof(query->snapshot));

  services::identity::accessSnapshot(&query->snapshot.identity);
  networking::wifi::accessSnapshot(&query->snapshot.network);
  power::sleep::accessStatus(&query->snapshot.sleep);
  services::data_logger::accessStatus(&query->snapshot.data_logger);
  StorageQuery storage_query = {
    .kind = query->preferred_storage,
    .snapshot = {},
  };
  hardware::storage::accessSnapshot(&storage_query);
  query->snapshot.storage = storage_query.snapshot;

  query->snapshot.uptime_seconds = millis() / 1000;
  query->snapshot.heap_free = ESP.getFreeHeap();
  query->snapshot.heap_total = ESP.getHeapSize();
  query->snapshot.heap_min_free = ESP.getMinFreeHeap();
  query->snapshot.heap_max_alloc = ESP.getMaxAllocHeap();
  query->snapshot.psram_total = ESP.getPsramSize();
  query->snapshot.psram_free = ESP.getFreePsram();
  query->snapshot.chip_cores = ESP.getChipCores();
  query->snapshot.chip_revision = ESP.getChipRevision();
  query->snapshot.cpu_mhz = ESP.getCpuFreqMHz();
  query->snapshot.flash_size = ESP.getFlashChipSize();
  query->snapshot.flash_speed_mhz = ESP.getFlashChipSpeed() / 1000000;
  query->snapshot.sketch_size = ESP.getSketchSize();
  query->snapshot.sketch_free = ESP.getFreeSketchSpace();
  query->snapshot.chip_temperature_celsius = temperatureRead();

  strncpy(query->snapshot.chip_model, ESP.getChipModel(), sizeof(query->snapshot.chip_model) - 1);
  strncpy(query->snapshot.sdk_version, ESP.getSdkVersion(), sizeof(query->snapshot.sdk_version) - 1);
  strncpy(query->snapshot.idf_version, esp_get_idf_version(), sizeof(query->snapshot.idf_version) - 1);
  strncpy(query->snapshot.arduino_version, ESP_ARDUINO_VERSION_STR, sizeof(query->snapshot.arduino_version) - 1);
  strncpy(query->snapshot.sketch_md5, ESP.getSketchMD5().c_str(), sizeof(query->snapshot.sketch_md5) - 1);
  return true;
}
