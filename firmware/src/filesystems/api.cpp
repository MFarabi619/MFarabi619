#include "api.h"

#include "../hardware/storage.h"

#include <LittleFS.h>
#include <SD.h>

bool filesystems::api::isSensitivePath(const String &path) {
  return path == "/.ssh" || path.startsWith("/.ssh/")
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
