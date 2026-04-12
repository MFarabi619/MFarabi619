#ifdef PIO_UNIT_TESTING

#include "../config.h"
#include "../testing/it.h"

namespace hardware::system { void test(void); }

#include <Arduino.h>
#include <Esp.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

// ─────────────────────────────────────────────────────────────────────────────
//  Chip temperature
// ─────────────────────────────────────────────────────────────────────────────

static void system_test_temperature_read(void) {
  TEST_MESSAGE("user reads internal chip temperature");

  float temp = temperatureRead();
  char msg[64];
  snprintf(msg, sizeof(msg), "chip temperature: %.1f C", temp);
  TEST_MESSAGE(msg);

  TEST_ASSERT_FLOAT_WITHIN_MESSAGE(50.0f, 50.0f, temp,
    "device: chip temperature outside 0-100 C range");
}

// ─────────────────────────────────────────────────────────────────────────────
//  FreeRTOS task list
// ─────────────────────────────────────────────────────────────────────────────

static void system_test_task_list(void) {
  TEST_MESSAGE("user lists all FreeRTOS tasks");

  uint32_t count = uxTaskGetNumberOfTasks();
  TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(0, count,
    "device: no tasks running");

  TaskStatus_t *tasks = (TaskStatus_t *)malloc(count * sizeof(TaskStatus_t));
  TEST_ASSERT_NOT_NULL_MESSAGE(tasks, "device: malloc failed for task list");

  uint32_t total_runtime = 0;
  uint32_t filled = uxTaskGetSystemState(tasks, count, &total_runtime);

  static const char *states[] = {"Running", "Ready", "Blocked", "Suspend", "Deleted", "Invalid"};

  for (uint32_t i = 0; i < filled; i++) {
    int state = (int)tasks[i].eCurrentState;
    if (state > 5) state = 5;
    int core = (int)tasks[i].xCoreID;
    char core_str[4];
    if (core == tskNO_AFFINITY) snprintf(core_str, sizeof(core_str), "*");
    else snprintf(core_str, sizeof(core_str), "%d", core);

    char line[80];
    snprintf(line, sizeof(line), "  %-16s %8s prio=%lu stack=%lu core=%s",
             tasks[i].pcTaskName, states[state],
             (unsigned long)tasks[i].uxCurrentPriority,
             (unsigned long)tasks[i].usStackHighWaterMark, core_str);
    TEST_MESSAGE(line);
  }

  free(tasks);

  char msg[32];
  snprintf(msg, sizeof(msg), "%lu tasks total", (unsigned long)filled);
  TEST_MESSAGE(msg);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Firmware integrity (sketch MD5, size, free space)
// ─────────────────────────────────────────────────────────────────────────────

static void system_test_sketch_md5(void) {
  TEST_MESSAGE("user verifies firmware integrity hash");

  String md5 = ESP.getSketchMD5();
  TEST_ASSERT_EQUAL_UINT32_MESSAGE(32, md5.length(),
    "device: sketch MD5 should be 32-char hex string");

  char msg[64];
  snprintf(msg, sizeof(msg), "sketch MD5: %s", md5.c_str());
  TEST_MESSAGE(msg);
}

static void system_test_sketch_size(void) {
  TEST_MESSAGE("user verifies firmware size and free OTA space");

  uint32_t sketch_size = ESP.getSketchSize();
  uint32_t free_space = ESP.getFreeSketchSpace();

  TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(0, sketch_size,
    "device: sketch size should be > 0");
  TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(0, free_space,
    "device: free sketch space should be > 0");

  char msg[80];
  snprintf(msg, sizeof(msg), "sketch: %lu KB, free OTA: %lu KB",
           (unsigned long)(sketch_size / 1024),
           (unsigned long)(free_space / 1024));
  TEST_MESSAGE(msg);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Watchdog timer
// ─────────────────────────────────────────────────────────────────────────────

static void system_test_watchdog(void) {
  TEST_MESSAGE("user verifies watchdog can be enabled and fed");

  // These should not crash
  enableLoopWDT();
  feedLoopWDT();
  feedLoopWDT();
  disableLoopWDT();

  TEST_MESSAGE("enableLoopWDT / feedLoopWDT / disableLoopWDT all safe");
}

// ─────────────────────────────────────────────────────────────────────────────
//  Heap fragmentation
// ─────────────────────────────────────────────────────────────────────────────

static void system_test_heap_fragmentation(void) {
  TEST_MESSAGE("user checks heap fragmentation");

  uint32_t free_heap = ESP.getFreeHeap();
  uint32_t max_alloc = ESP.getMaxAllocHeap();
  uint32_t min_free = ESP.getMinFreeHeap();
  uint32_t total = ESP.getHeapSize();

  TEST_ASSERT_LESS_OR_EQUAL_UINT32_MESSAGE(free_heap, max_alloc,
    "device: max alloc should be <= free heap");
  TEST_ASSERT_LESS_OR_EQUAL_UINT32_MESSAGE(total, free_heap,
    "device: free heap should be <= total heap");

  uint32_t frag_pct = (free_heap > 0)
    ? 100 - (max_alloc * 100 / free_heap)
    : 0;

  char msg[96];
  snprintf(msg, sizeof(msg),
           "heap: %lu/%lu KB free, max_alloc=%lu KB, min_free=%lu KB, frag=%lu%%",
           (unsigned long)(free_heap / 1024),
           (unsigned long)(total / 1024),
           (unsigned long)(max_alloc / 1024),
           (unsigned long)(min_free / 1024),
           (unsigned long)frag_pct);
  TEST_MESSAGE(msg);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Flash chip info
// ─────────────────────────────────────────────────────────────────────────────

static void system_test_flash_chip_info(void) {
  TEST_MESSAGE("user reads flash chip configuration");

  uint32_t flash_size = ESP.getFlashChipSize();
  uint32_t flash_speed = ESP.getFlashChipSpeed();
  FlashMode_t flash_mode = ESP.getFlashChipMode();

  TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(0, flash_size,
    "device: flash size should be > 0");
  TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(0, flash_speed,
    "device: flash speed should be > 0");

  const char *mode_str = "unknown";
  switch (flash_mode) {
    case FM_QIO:  mode_str = "QIO"; break;
    case FM_QOUT: mode_str = "QOUT"; break;
    case FM_DIO:  mode_str = "DIO"; break;
    case FM_DOUT: mode_str = "DOUT"; break;
    default: break;
  }

  char msg[80];
  snprintf(msg, sizeof(msg), "flash: %lu MB, %lu MHz, mode=%s",
           (unsigned long)(flash_size / (1024 * 1024)),
           (unsigned long)(flash_speed / 1000000),
           mode_str);
  TEST_MESSAGE(msg);
}

// ─────────────────────────────────────────────────────────────────────────────
//  CPU frequency
// ─────────────────────────────────────────────────────────────────────────────

static void system_test_cpu_frequency(void) {
  TEST_MESSAGE("user reads CPU frequency");

  uint32_t freq = ESP.getCpuFreqMHz();
  TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(0, freq,
    "device: CPU frequency should be > 0");

  char msg[48];
  snprintf(msg, sizeof(msg), "CPU: %lu MHz", (unsigned long)freq);
  TEST_MESSAGE(msg);

  // ESP32-S3 default is 240 MHz
  TEST_ASSERT_EQUAL_UINT32_MESSAGE(240, freq,
    "device: ESP32-S3 should default to 240 MHz");
}

// ─────────────────────────────────────────────────────────────────────────────
//  Version strings
// ─────────────────────────────────────────────────────────────────────────────

static void system_test_version_strings(void) {
  TEST_MESSAGE("user reads firmware and SDK version strings");

  const char *sdk = ESP.getSdkVersion();
  const char *idf = esp_get_idf_version();
  const char *chip = ESP.getChipModel();

  TEST_ASSERT_NOT_NULL(sdk);
  TEST_ASSERT_NOT_NULL(idf);
  TEST_ASSERT_NOT_NULL(chip);

  char msg[128];
  snprintf(msg, sizeof(msg), "chip=%s cores=%u rev=%u arduino=%s idf=%s",
           chip, ESP.getChipCores(), ESP.getChipRevision(),
           ESP_ARDUINO_VERSION_STR, idf);
  TEST_MESSAGE(msg);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Runner
// ─────────────────────────────────────────────────────────────────────────────

void hardware::system::test(void) {
  it("user observes chip temperature is readable",
     system_test_temperature_read);
  it("user observes FreeRTOS task list",
     system_test_task_list);
  it("user observes firmware MD5 integrity hash",
     system_test_sketch_md5);
  it("user observes firmware size and OTA free space",
     system_test_sketch_size);
  it("user observes watchdog timer is safe to enable and feed",
     system_test_watchdog);
  it("user observes heap fragmentation metrics",
     system_test_heap_fragmentation);
  it("user observes flash chip configuration",
     system_test_flash_chip_info);
  it("user observes CPU frequency is 240 MHz",
     system_test_cpu_frequency);
  it("user observes firmware and SDK version strings",
     system_test_version_strings);
}

#endif
