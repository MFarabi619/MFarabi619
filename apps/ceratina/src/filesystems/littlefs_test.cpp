#ifdef PIO_UNIT_TESTING

#include <config.h>
#include <testing/utils.h>

namespace filesystems::littlefs { void test(void); }

#include <Arduino.h>
#include <LittleFS.h>
#include <stdio.h>

static void test_littlefs_mounts(void) {
  WHEN("LittleFS is mounted");
  TEST_ASSERT_TRUE_MESSAGE(LittleFS.begin(true),
    "device: LittleFS.begin() failed");

  size_t total = LittleFS.totalBytes();
  size_t used  = LittleFS.usedBytes();
  TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(0, total,
    "device: LittleFS total is 0");

  TEST_PRINTF("%u KB total, %u KB used", total / 1024, used / 1024);
}

static void test_littlefs_write_read_roundtrip(void) {
  GIVEN("LittleFS is mounted");
  LittleFS.begin(false);

  WHEN("a file is written and read back");

  const char *path = "/.test_lfs.tmp";
  const char *payload = "littlefs roundtrip test";

  File writer = LittleFS.open(path, FILE_WRITE);
  TEST_ASSERT_TRUE_MESSAGE((bool)writer, "device: open for write failed");
  writer.print(payload);
  writer.close();

  File reader = LittleFS.open(path, FILE_READ);
  TEST_ASSERT_TRUE_MESSAGE((bool)reader, "device: open for read failed");
  char buf[64] = {0};
  reader.readBytes(buf, sizeof(buf) - 1);
  reader.close();

  TEST_ASSERT_EQUAL_STRING_MESSAGE(payload, buf,
    "device: LittleFS read doesn't match write");

  LittleFS.remove(path);
}

static void test_littlefs_ssh_dir_persists(void) {
  GIVEN("LittleFS is mounted");
  LittleFS.begin(false);

  WHEN("a file is written to .ssh and LittleFS is remounted");

  if (!LittleFS.exists("/.ssh")) {
    LittleFS.mkdir("/.ssh");
  }
  TEST_ASSERT_TRUE_MESSAGE(LittleFS.exists("/.ssh"),
    "device: /.ssh directory missing");

  // Write a test file inside .ssh
  File f = LittleFS.open("/.ssh/.test_persist", FILE_WRITE);
  f.print("persist");
  f.close();

  // Remount
  LittleFS.end();
  LittleFS.begin(true);

  TEST_ASSERT_TRUE_MESSAGE(LittleFS.exists("/.ssh/.test_persist"),
    "device: file in /.ssh did not survive remount");

  LittleFS.remove("/.ssh/.test_persist");
}

static void test_littlefs_mkdir_nested(void) {
  GIVEN("LittleFS is mounted");
  LittleFS.begin(false);

  WHEN("nested directories are created");

  LittleFS.mkdir("/.test_nest");
  LittleFS.mkdir("/.test_nest/deep");

  File f = LittleFS.open("/.test_nest/deep/file.txt", FILE_WRITE);
  TEST_ASSERT_TRUE_MESSAGE((bool)f, "device: write to nested dir failed");
  f.print("deep");
  f.close();

  TEST_ASSERT_TRUE_MESSAGE(LittleFS.exists("/.test_nest/deep/file.txt"),
    "device: nested file missing");

  LittleFS.remove("/.test_nest/deep/file.txt");
  LittleFS.rmdir("/.test_nest/deep");
  LittleFS.rmdir("/.test_nest");
}

static void test_littlefs_hostkey_path(void) {
  GIVEN("LittleFS is mounted");
  LittleFS.begin(false);

  WHEN("a host key is written and read via both APIs");

  LittleFS.mkdir("/.ssh");
  File writer = LittleFS.open(config::ssh::HOSTKEY_PATH, FILE_WRITE);
  TEST_ASSERT_TRUE_MESSAGE((bool)writer, "device: cannot open hostkey path for writing");
  writer.print("fake-key-data");
  writer.close();

  TEST_ASSERT_TRUE_MESSAGE(LittleFS.exists(config::ssh::HOSTKEY_PATH),
    "device: hostkey file missing via LittleFS API");

  // Verify the VFS path (what libssh uses) resolves to the same file
  String vfs_path = String(LittleFS.mountpoint()) + config::ssh::HOSTKEY_PATH;
  FILE *vfs_fp = fopen(vfs_path.c_str(), "r");
  TEST_ASSERT_NOT_NULL_MESSAGE(vfs_fp,
    "device: fopen via VFS mountpoint failed — paths may be inconsistent");
  char vfs_buf[32] = {0};
  fread(vfs_buf, 1, sizeof(vfs_buf) - 1, vfs_fp);
  fclose(vfs_fp);

  TEST_ASSERT_EQUAL_STRING_MESSAGE("fake-key-data", vfs_buf,
    "device: VFS path content doesn't match LittleFS write");

  // Remount and verify persistence
  LittleFS.end();
  LittleFS.begin(false);

  TEST_ASSERT_TRUE_MESSAGE(LittleFS.exists(config::ssh::HOSTKEY_PATH),
    "device: hostkey file missing after remount");

  LittleFS.remove(config::ssh::HOSTKEY_PATH);
}

static void test_littlefs_rmdir_non_empty(void) {
  GIVEN("LittleFS is mounted");
  LittleFS.begin(false);

  WHEN("rmdir is called on a non-empty directory");

  LittleFS.mkdir("/.test_rmdir");
  File f = LittleFS.open("/.test_rmdir/child.txt", FILE_WRITE);
  TEST_ASSERT_TRUE_MESSAGE((bool)f, "device: failed to create file in dir");
  f.print("content");
  f.close();

  bool result = LittleFS.rmdir("/.test_rmdir");
  TEST_PRINTF("rmdir on non-empty dir returned: %s",
           result ? "true (recursive!)" : "false (non-recursive)");
  TEST_ASSERT_FALSE_MESSAGE(result,
    "device: rmdir removed a non-empty directory — it IS recursive");

  LittleFS.remove("/.test_rmdir/child.txt");
  LittleFS.rmdir("/.test_rmdir");
}

static void test_littlefs_remove_on_directory(void) {
  GIVEN("LittleFS is mounted");
  LittleFS.begin(false);

  WHEN("remove() is called on a directory");

  LittleFS.mkdir("/.test_rm_dir");
  TEST_ASSERT_TRUE_MESSAGE(LittleFS.exists("/.test_rm_dir"),
    "device: mkdir failed");

  bool result = LittleFS.remove("/.test_rm_dir");
  TEST_PRINTF("remove() on directory returned: %s",
           result ? "true (handles dirs)" : "false (files only)");

  if (LittleFS.exists("/.test_rm_dir"))
    LittleFS.rmdir("/.test_rm_dir");
}

static void test_littlefs_rename(void) {
  GIVEN("LittleFS is mounted");
  LittleFS.begin(false);

  WHEN("a file is renamed");

  const char *src = "/.test_rename_src.tmp";
  const char *dst = "/.test_rename_dst.tmp";
  const char *payload = "rename-test-payload";

  if (LittleFS.exists(dst)) LittleFS.remove(dst);

  File f = LittleFS.open(src, FILE_WRITE);
  TEST_ASSERT_TRUE_MESSAGE((bool)f, "device: open src for write failed");
  f.print(payload);
  f.close();

  bool renamed = LittleFS.rename(src, dst);
  TEST_ASSERT_TRUE_MESSAGE(renamed, "device: rename returned false");
  TEST_ASSERT_FALSE_MESSAGE(LittleFS.exists(src),
    "device: source still exists after rename");
  TEST_ASSERT_TRUE_MESSAGE(LittleFS.exists(dst),
    "device: destination missing after rename");

  File reader = LittleFS.open(dst, FILE_READ);
  TEST_ASSERT_TRUE_MESSAGE((bool)reader, "device: open dst for read failed");
  char buf[64] = {0};
  reader.readBytes(buf, sizeof(buf) - 1);
  reader.close();

  TEST_ASSERT_EQUAL_STRING_MESSAGE(payload, buf,
    "device: renamed file content doesn't match");

  LittleFS.remove(dst);
}

void filesystems::littlefs::test(void) {
  MODULE("LittleFS");
  RUN_TEST(test_littlefs_mounts);
  RUN_TEST(test_littlefs_write_read_roundtrip);
  RUN_TEST(test_littlefs_ssh_dir_persists);
  RUN_TEST(test_littlefs_mkdir_nested);
  RUN_TEST(test_littlefs_hostkey_path);
  RUN_TEST(test_littlefs_rmdir_non_empty);
  RUN_TEST(test_littlefs_remove_on_directory);
  RUN_TEST(test_littlefs_rename);
}

#endif
