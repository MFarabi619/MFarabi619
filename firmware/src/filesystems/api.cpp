#include "api.h"

#include <storage.h>

#include <LittleFS.h>
#include <SD.h>

bool filesystems::api::isSensitivePath(const String &path) {
  return path == "/.ssh" || path == ".ssh"
      || path.startsWith("/.ssh/") || path.startsWith(".ssh/")
      || path == config::ssh::HOSTKEY_PATH;
}

bool filesystems::api::resolveTarget(FilesystemResolveCommand *command) {
  if (!command) return false;
  command->target = {nullptr, "", false};

  const char *prefix = "/api/filesystem/";
  String remainder = command->url.substring(strlen(prefix));

  if (remainder.startsWith("sd")) {
    String path = remainder.substring(2);
    if (path.isEmpty()) path = "/";
    if (hardware::storage::ensureSD()) {
      command->target = {&SD, path, true};
      return true;
    }
    command->target = {nullptr, path, false};
    return false;
  }

  if (remainder.startsWith("littlefs")) {
    String path = remainder.substring(8);
    if (path.isEmpty()) path = "/";
    if (hardware::storage::ensureLittleFS()) {
      command->target = {&LittleFS, path, true};
      return true;
    }
    command->target = {nullptr, path, false};
    return false;
  }

  return false;
}

void filesystems::api::listDirectory(fs::FS &filesystem, const String &path, JsonArray &out) {
  File dir = filesystem.open(path);
  if (!dir || !dir.isDirectory()) return;

  File entry = dir.openNextFile();
  while (entry) {
    String name = String(entry.name());
    if (!filesystems::api::isSensitivePath(name)) {
      JsonObject object = out.add<JsonObject>();
      object["name"] = name;
      object["size"] = (unsigned long long)entry.size();
      object["dir"] = entry.isDirectory();
      object["last_write_unix"] = (unsigned long long)entry.getLastWrite();
    }
    entry = dir.openNextFile();
  }

  dir.close();
}

bool filesystems::api::removeRecursive(fs::FS &filesystem, const String &path) {
  File entry = filesystem.open(path);
  if (!entry) return false;

  if (!entry.isDirectory()) {
    entry.close();
    return filesystem.remove(path);
  }

  entry.close();
  File dir = filesystem.open(path);
  File child = dir.openNextFile();
  while (child) {
    String child_name = String(child.name());
    bool is_directory = child.isDirectory();
    child.close();
    String child_path = (path == "/") ? "/" + child_name : path + "/" + child_name;

    if (is_directory) {
      if (!filesystems::api::removeRecursive(filesystem, child_path)) {
        dir.close();
        return false;
      }
    } else {
      if (!filesystem.remove(child_path)) {
        dir.close();
        return false;
      }
    }

    child = dir.openNextFile();
  }

  dir.close();
  return filesystem.rmdir(path);
}

#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

namespace filesystems::api { void test(void); }

static void test_api_sensitive_path_with_slash(void) {
  GIVEN("a path starting with /.ssh");
  THEN("it is detected as sensitive");
  TEST_ASSERT_TRUE_MESSAGE(filesystems::api::isSensitivePath("/.ssh"),
    "device: /.ssh must be detected as sensitive");
}

static void test_api_sensitive_path_without_slash(void) {
  GIVEN("a path .ssh without leading slash");
  THEN("it is detected as sensitive");
  TEST_ASSERT_TRUE_MESSAGE(filesystems::api::isSensitivePath(".ssh"),
    "device: .ssh without leading slash must be sensitive");
}

static void test_api_sensitive_path_nested(void) {
  GIVEN("nested paths under .ssh");
  THEN("they are detected as sensitive");
  TEST_ASSERT_TRUE_MESSAGE(filesystems::api::isSensitivePath("/.ssh/host_key"),
    "device: /.ssh/host_key must be sensitive");
  TEST_ASSERT_TRUE_MESSAGE(filesystems::api::isSensitivePath(".ssh/authorized_keys"),
    "device: .ssh/authorized_keys must be sensitive");
}

static void test_api_normal_path_not_sensitive(void) {
  GIVEN("normal file paths");
  THEN("they are not flagged as sensitive");
  TEST_ASSERT_FALSE_MESSAGE(filesystems::api::isSensitivePath("/data.csv"),
    "device: /data.csv must not be sensitive");
  TEST_ASSERT_FALSE_MESSAGE(filesystems::api::isSensitivePath("/public/index.html"),
    "device: /public/index.html must not be sensitive");
  TEST_ASSERT_FALSE_MESSAGE(filesystems::api::isSensitivePath("data.csv"),
    "device: data.csv must not be sensitive");
}

void filesystems::api::test(void) {
  RUN_TEST(test_api_sensitive_path_with_slash);
  RUN_TEST(test_api_sensitive_path_without_slash);
  RUN_TEST(test_api_sensitive_path_nested);
  RUN_TEST(test_api_normal_path_not_sensitive);
}

#endif
