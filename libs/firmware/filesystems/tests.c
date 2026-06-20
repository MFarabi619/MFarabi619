#include <string.h>

#include <zephyr/fs/fs.h>
#include <zephyr/ztest.h>

#include <bdd.h>

/* ============================ fs API suite ============================ */

struct fs_fixture {
  const char *path;
};

static struct fs_fixture fs_fixture = {.path = "/lfs/fs_test.bin"};

static void *fs_setup(void) { return &fs_fixture; }

static void fs_unlink_before(const struct ztest_unit_test *test, void *data) {
  if (strcmp(test->test_suite_name, "fs") == 0) {
    struct fs_fixture *f = data;
    struct fs_dirent entry;
    if (fs_stat(f->path, &entry) == 0) {
      fs_unlink(f->path);
    }
  }
}

ZTEST_RULE(fs_clean, fs_unlink_before, NULL);

ZTEST_SUITE(fs, NULL, fs_setup, NULL, NULL, NULL);

ZTEST_F(fs, open_create_close_succeeds) {
  struct fs_file_t file;
  fs_file_t_init(&file);

  GIVEN("an unused path on the littlefs mount");
  WHEN("fs_open is called with FS_O_CREATE | FS_O_WRITE");
  zassert_equal(fs_open(&file, fixture->path, FS_O_CREATE | FS_O_WRITE), 0,
                "fs_open failed");
  THEN("the file is created and fs_close returns zero");
  zassert_equal(fs_close(&file), 0, "fs_close failed");
}

ZTEST_F(fs, write_then_read_returns_same_bytes) {
  const char payload[] = "hello, filesystem!";
  char buffer[sizeof(payload)] = {0};
  struct fs_file_t file;
  fs_file_t_init(&file);

  GIVEN("a freshly created file");
  zassert_equal(fs_open(&file, fixture->path, FS_O_CREATE | FS_O_RDWR), 0, "");
  WHEN("a payload is written and the file rewound for reading");
  zassert_equal(fs_write(&file, payload, sizeof(payload)), sizeof(payload), "");
  zassert_equal(fs_seek(&file, 0, FS_SEEK_SET), 0, "");
  THEN("fs_read returns the same bytes");
  zassert_equal(fs_read(&file, buffer, sizeof(buffer)), sizeof(buffer), "");
  zassert_mem_equal(buffer, payload, sizeof(payload), "");
  fs_close(&file);
}

ZTEST_F(fs, file_persists_across_close_and_reopen) {
  const char payload[] = "persisted";
  char buffer[sizeof(payload)] = {0};
  struct fs_file_t file;
  fs_file_t_init(&file);

  GIVEN("a payload written to a closed file");
  zassert_equal(fs_open(&file, fixture->path, FS_O_CREATE | FS_O_WRITE), 0, "");
  zassert_equal(fs_write(&file, payload, sizeof(payload)), sizeof(payload), "");
  zassert_equal(fs_close(&file), 0, "");

  WHEN("the file is reopened for reading");
  fs_file_t_init(&file);
  zassert_equal(fs_open(&file, fixture->path, FS_O_READ), 0, "");
  THEN("the contents are unchanged");
  zassert_equal(fs_read(&file, buffer, sizeof(buffer)), sizeof(buffer), "");
  zassert_mem_equal(buffer, payload, sizeof(payload), "");
  fs_close(&file);
}

ZTEST_F(fs, stat_reports_size_after_write) {
  const char payload[100] = {0};
  struct fs_file_t file;
  struct fs_dirent entry;
  fs_file_t_init(&file);

  GIVEN("a file with exactly 100 bytes written and closed");
  zassert_equal(fs_open(&file, fixture->path, FS_O_CREATE | FS_O_WRITE), 0, "");
  zassert_equal(fs_write(&file, payload, sizeof(payload)), sizeof(payload), "");
  zassert_equal(fs_close(&file), 0, "");

  WHEN("fs_stat is called on the path");
  zassert_equal(fs_stat(fixture->path, &entry), 0, "");
  THEN("the reported size is 100");
  zassert_equal(entry.size, 100, "size was %u", (unsigned int)entry.size);
}

ZTEST_F(fs, seek_set_then_read_returns_byte_at_offset) {
  const char payload[] = "ABCDEFGH";
  char byte = 0;
  struct fs_file_t file;
  fs_file_t_init(&file);

  GIVEN("a file containing the bytes 'ABCDEFGH'");
  zassert_equal(fs_open(&file, fixture->path, FS_O_CREATE | FS_O_RDWR), 0, "");
  zassert_equal(fs_write(&file, payload, 8), 8, "");
  WHEN("fs_seek to offset 3 followed by fs_read of 1 byte");
  zassert_equal(fs_seek(&file, 3, FS_SEEK_SET), 0, "");
  zassert_equal(fs_read(&file, &byte, 1), 1, "");
  THEN("the byte read is 'D'");
  zassert_equal(byte, 'D', "got 0x%02x", (unsigned int)byte);
  fs_close(&file);
}

ZTEST_F(fs, sync_returns_zero) {
  struct fs_file_t file;
  fs_file_t_init(&file);

  GIVEN("an open file with pending writes");
  zassert_equal(fs_open(&file, fixture->path, FS_O_CREATE | FS_O_WRITE), 0, "");
  zassert_equal(fs_write(&file, "x", 1), 1, "");
  WHEN("fs_sync is called");
  THEN("it returns zero");
  zassert_equal(fs_sync(&file), 0, "");
  fs_close(&file);
}

ZTEST_F(fs, truncate_shrinks_file) {
  const char payload[100] = {0};
  struct fs_file_t file;
  struct fs_dirent entry;
  fs_file_t_init(&file);

  GIVEN("a 100-byte file");
  zassert_equal(fs_open(&file, fixture->path, FS_O_CREATE | FS_O_RDWR), 0, "");
  zassert_equal(fs_write(&file, payload, sizeof(payload)), sizeof(payload), "");

  WHEN("fs_truncate shortens the file to 25 bytes");
  zassert_equal(fs_truncate(&file, 25), 0, "");
  zassert_equal(fs_close(&file), 0, "");
  THEN("fs_stat reports the new size");
  zassert_equal(fs_stat(fixture->path, &entry), 0, "");
  zassert_equal(entry.size, 25, "size was %u", (unsigned int)entry.size);
}

ZTEST_F(fs, unlink_removes_the_file) {
  struct fs_file_t file;
  struct fs_dirent entry;
  fs_file_t_init(&file);

  GIVEN("an existing file");
  zassert_equal(fs_open(&file, fixture->path, FS_O_CREATE | FS_O_WRITE), 0, "");
  zassert_equal(fs_close(&file), 0, "");
  zassert_equal(fs_stat(fixture->path, &entry), 0, "");

  WHEN("fs_unlink is called");
  zassert_equal(fs_unlink(fixture->path), 0, "");
  THEN("fs_stat returns -ENOENT");
  zassert_equal(fs_stat(fixture->path, &entry), -ENOENT, "");
}

