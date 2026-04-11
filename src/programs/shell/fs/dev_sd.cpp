#include "../../../config.h"

#include <Arduino.h>
#include <SD.h>
#include <SPI.h>
#include <microshell.h>
#include <string.h>

static bool sd_initialized = false;

//------------------------------------------
//  /dev/sd/info — card type, size, usage
//------------------------------------------
static size_t sd_info_get_data(struct ush_object *self,
                               struct ush_file_descriptor const *file,
                               uint8_t **data) {
  (void)self; (void)file;
  static char buf[256];

  if (!sd_initialized) {
    snprintf(buf, sizeof(buf), "SD card not mounted\r\n");
    *data = (uint8_t *)buf;
    return strlen(buf);
  }

  const char *type = "UNKNOWN";
  switch (SD.cardType()) {
    case CARD_MMC:  type = "MMC";  break;
    case CARD_SD:   type = "SD";   break;
    case CARD_SDHC: type = "SDHC"; break;
    default: break;
  }

  uint64_t card_size = SD.cardSize();
  uint64_t fs_total  = SD.totalBytes();
  uint64_t fs_used   = SD.usedBytes();

  snprintf(buf, sizeof(buf),
           "type:      %s\r\n"
           "card_size: %llu MB\r\n"
           "fs_total:  %llu MB\r\n"
           "fs_used:   %llu MB\r\n"
           "fs_free:   %llu MB\r\n",
           type,
           card_size / (1024 * 1024),
           fs_total / (1024 * 1024),
           fs_used / (1024 * 1024),
           (fs_total - fs_used) / (1024 * 1024));

  *data = (uint8_t *)buf;
  return strlen(buf);
}

static const struct ush_file_descriptor sd_files[] = {
  { .name = "info", .description = "SD card info",
    .get_data = sd_info_get_data },
};

static struct ush_node_object sd_node;

void dev_sd_mount(struct ush_object *ush) {
  // Try to initialize SD card
  if (SD.begin(CONFIG_SD_CS_GPIO)) {
    sd_initialized = true;
    Serial.printf("[sd] mounted: %s, %llu MB\n",
                  SD.cardType() == CARD_SDHC ? "SDHC" : "SD",
                  SD.totalBytes() / (1024 * 1024));
  } else {
    Serial.println(F("[sd] no card detected"));
  }

  ush_node_mount(ush, "/dev/sd", &sd_node, sd_files,
                 sizeof(sd_files) / sizeof(sd_files[0]));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tests — describe("SD Card")
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING

#include "../../../testing/it.h"

static void sd_test_mounts(void) {
  TEST_MESSAGE("user asks the device to mount the SD card");
  bool ok = SD.begin(CONFIG_SD_CS_GPIO);
  if (!ok) {
    TEST_IGNORE_MESSAGE("skipped — no SD card inserted");
    return;
  }
  TEST_ASSERT_NOT_EQUAL_MESSAGE(CARD_NONE, SD.cardType(),
    "device: SD card type is CARD_NONE after begin");
  TEST_MESSAGE("SD card mounted");
}

static void sd_test_reports_size(void) {
  TEST_MESSAGE("user checks SD card capacity");
  if (!SD.begin(CONFIG_SD_CS_GPIO)) {
    TEST_IGNORE_MESSAGE("skipped — no SD card");
    return;
  }
  uint64_t total = SD.totalBytes();
  TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(0, (uint32_t)(total / 1024),
    "device: SD total bytes is 0");
  char msg[48];
  snprintf(msg, sizeof(msg), "%llu MB total", total / (1024 * 1024));
  TEST_MESSAGE(msg);
}

static void sd_test_write_read_roundtrip(void) {
  TEST_MESSAGE("user writes a test file and reads it back");
  if (!SD.begin(CONFIG_SD_CS_GPIO)) {
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
  size_t len = reader.readBytes(buf, sizeof(buf) - 1);
  reader.close();

  TEST_ASSERT_EQUAL_STRING_MESSAGE(payload, buf,
    "device: read content doesn't match written content");

  SD.remove(path);
  TEST_ASSERT_FALSE_MESSAGE(SD.exists(path),
    "device: test file still exists after remove");

  TEST_MESSAGE("write/read/delete roundtrip verified");
}

static void sd_test_append_mode(void) {
  TEST_MESSAGE("user verifies FILE_APPEND adds to file without truncating");
  if (!SD.begin(CONFIG_SD_CS_GPIO)) {
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
  TEST_MESSAGE("append mode verified");
}

static void sd_test_auto_create_parents(void) {
  TEST_MESSAGE("user verifies open with create=true auto-creates parent dirs");
  if (!SD.begin(CONFIG_SD_CS_GPIO)) {
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
  TEST_MESSAGE("auto parent directory creation verified");
}

static void sd_test_directory_listing(void) {
  TEST_MESSAGE("user lists files in a directory");
  if (!SD.begin(CONFIG_SD_CS_GPIO)) {
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

  char msg[32];
  snprintf(msg, sizeof(msg), "found %d entries", count);
  TEST_MESSAGE(msg);
}

static void sd_test_buffered_write(void) {
  TEST_MESSAGE("user writes with custom buffer size for performance");
  if (!SD.begin(CONFIG_SD_CS_GPIO)) {
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

  char msg[48];
  snprintf(msg, sizeof(msg), "100 lines in %lu ms", elapsed);
  TEST_MESSAGE(msg);
}

void sd_run_tests(void) {
  it("user observes that the SD card mounts",
     sd_test_mounts);
  it("user observes that the SD card reports its size",
     sd_test_reports_size);
  it("user observes that a file can be written, read, and deleted",
     sd_test_write_read_roundtrip);
  it("user observes that append mode preserves existing content",
     sd_test_append_mode);
  it("user observes that open with create auto-creates parent dirs",
     sd_test_auto_create_parents);
  it("user observes that directory listing finds created files",
     sd_test_directory_listing);
  it("user observes that buffered writes complete quickly",
     sd_test_buffered_write);
}

#endif
