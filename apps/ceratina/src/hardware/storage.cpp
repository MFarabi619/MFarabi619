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

#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

static void test_sd_mounts(void) {
  WHEN("the SD card is mounted");
  bool ok = hardware::storage::ensureSD();
  if (!ok) {
    TEST_IGNORE_MESSAGE("skipped — no SD card inserted");
    return;
  }
  TEST_ASSERT_NOT_EQUAL_MESSAGE(CARD_NONE, SD.cardType(),
    "device: SD card type is CARD_NONE after begin");
}

static void test_sd_reports_size(void) {
  WHEN("the SD card capacity is queried");
  if (!hardware::storage::ensureSD()) {
    TEST_IGNORE_MESSAGE("skipped — no SD card");
    return;
  }
  uint64_t total = SD.totalBytes();
  TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(0, (uint32_t)(total / 1024),
    "device: SD total bytes is 0");
  TEST_PRINTF("%llu MB total", total / (1024 * 1024));
}

static void test_sd_write_read_roundtrip(void) {
  WHEN("a file is written, read, and deleted");
  if (!hardware::storage::ensureSD()) {
    TEST_IGNORE_MESSAGE("skipped — no SD card");
    return;
  }

  const char *path = "/.test_roundtrip.tmp";
  const char *payload = "microvisor sd test";

  File writer = SD.open(path, FILE_WRITE);
  TEST_ASSERT_TRUE_MESSAGE((bool)writer,
    "device: failed to open file for writing");
  writer.print(payload);
  writer.close();

  File reader = SD.open(path, FILE_READ);
  TEST_ASSERT_TRUE_MESSAGE((bool)reader,
    "device: failed to open file for reading");
  char buf[64] = {0};
  reader.readBytes(buf, sizeof(buf) - 1);
  reader.close();

  TEST_ASSERT_EQUAL_STRING_MESSAGE(payload, buf,
    "device: read content doesn't match written content");

  SD.remove(path);
  TEST_ASSERT_FALSE_MESSAGE(SD.exists(path),
    "device: test file still exists after remove");

}

static void test_sd_append_mode(void) {
  WHEN("a file is appended to");
  if (!hardware::storage::ensureSD()) {
    TEST_IGNORE_MESSAGE("skipped — no SD card");
    return;
  }

  const char *path = "/.test_append.tmp";
  SD.remove(path);

  File f1 = SD.open(path, FILE_WRITE);
  f1.print("hello");
  f1.close();

  File f2 = SD.open(path, FILE_APPEND);
  f2.print(" world");
  f2.close();

  File f3 = SD.open(path, FILE_READ);
  char buf[32] = {0};
  f3.readBytes(buf, sizeof(buf) - 1);
  f3.close();

  TEST_ASSERT_EQUAL_STRING_MESSAGE("hello world", buf,
    "device: append did not preserve original content");

  SD.remove(path);
}

static void test_sd_auto_create_parents(void) {
  WHEN("a file is opened with create=true in a nested path");
  if (!hardware::storage::ensureSD()) {
    TEST_IGNORE_MESSAGE("skipped — no SD card");
    return;
  }

  const char *path = "/.test_nested/sub/file.txt";

  File f = SD.open(path, FILE_WRITE, true);
  TEST_ASSERT_TRUE_MESSAGE((bool)f,
    "device: open with create=true failed");
  f.print("nested");
  f.close();

  TEST_ASSERT_TRUE_MESSAGE(SD.exists(path),
    "device: nested file does not exist after create");

  SD.remove(path);
  SD.rmdir("/.test_nested/sub");
  SD.rmdir("/.test_nested");
}

static void test_sd_directory_listing(void) {
  WHEN("files are created and the directory is listed");
  if (!hardware::storage::ensureSD()) {
    TEST_IGNORE_MESSAGE("skipped — no SD card");
    return;
  }

  SD.mkdir("/.test_dir");
  File f1 = SD.open("/.test_dir/a.txt", FILE_WRITE);
  f1.print("a");
  f1.close();
  File f2 = SD.open("/.test_dir/b.txt", FILE_WRITE);
  f2.print("b");
  f2.close();

  File dir = SD.open("/.test_dir");
  TEST_ASSERT_TRUE_MESSAGE(dir.isDirectory(),
    "device: opened path is not a directory");

  int count = 0;
  File entry = dir.openNextFile();
  while (entry) {
    count++;
    entry = dir.openNextFile();
  }
  dir.close();

  TEST_ASSERT_GREATER_OR_EQUAL_INT_MESSAGE(2, count,
    "device: expected at least 2 files in test directory");

  SD.remove("/.test_dir/a.txt");
  SD.remove("/.test_dir/b.txt");
  SD.rmdir("/.test_dir");

  TEST_PRINTF("found %d entries", count);
}

static void test_sd_buffered_write(void) {
  WHEN("data is written with a custom buffer size");
  if (!hardware::storage::ensureSD()) {
    TEST_IGNORE_MESSAGE("skipped — no SD card");
    return;
  }

  const char *path = "/.test_buffered.tmp";
  File f = SD.open(path, FILE_WRITE);
  TEST_ASSERT_TRUE_MESSAGE((bool)f, "device: open failed");
  f.setBufferSize(8192);

  unsigned long start = millis();
  for (int i = 0; i < 100; i++) {
    f.println("0123456789abcdef0123456789abcdef0123456789abcdef");
  }
  f.flush();
  f.close();
  unsigned long elapsed = millis() - start;

  TEST_ASSERT_TRUE_MESSAGE(SD.exists(path),
    "device: buffered write file missing");

  File check = SD.open(path, FILE_READ);
  TEST_ASSERT_GREATER_THAN_MESSAGE(0, (int)check.size(),
    "device: buffered write file is empty");
  check.close();

  SD.remove(path);

  TEST_PRINTF("100 lines in %lu ms", elapsed);
}

namespace filesystems::sd { void test(void); }

void filesystems::sd::test(void) {
  MODULE("SD");
  RUN_TEST(test_sd_mounts);
  RUN_TEST(test_sd_reports_size);
  RUN_TEST(test_sd_write_read_roundtrip);
  RUN_TEST(test_sd_append_mode);
  RUN_TEST(test_sd_auto_create_parents);
  RUN_TEST(test_sd_directory_listing);
  RUN_TEST(test_sd_buffered_write);
}

#endif
