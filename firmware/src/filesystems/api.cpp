#include "api.h"

#include "../hardware/storage.h"

#include <LittleFS.h>
#include <SD.h>

#if 0
bool filesystems::api::isSensitivePath(const String &path) {
  return path == "/.ssh" || path.startsWith("/.ssh/")
      || path == config::ssh::HOSTKEY_PATH;
}

bool filesystems::api::resolveTarget(FilesystemResolveCommand *command) {
  if (!command) return false;
  command->target = {FilesystemKind::SD, "", false};

  const char *prefix = "/api/filesystem/";
  String remainder = command->url.substring(strlen(prefix));

  if (remainder.startsWith("sd")) {
    String path = remainder.substring(2);
    if (path.isEmpty()) path = "/";
    if (hardware::storage::ensureSD()) {
      command->target = {FilesystemKind::SD, path, true};
      return true;
    }
    command->target = {FilesystemKind::SD, path, false};
    return false;
  }

  if (remainder.startsWith("littlefs")) {
    String path = remainder.substring(8);
    if (path.isEmpty()) path = "/";
    if (hardware::storage::ensureLittleFS()) {
      command->target = {FilesystemKind::LittleFS, path, true};
      return true;
    }
    command->target = {FilesystemKind::LittleFS, path, false};
    return false;
  }

  return false;
}

void filesystems::api::listDirectory(FilesystemKind kind, const String &path, JsonArray &out) {
  if (kind == FilesystemKind::LittleFS) {
    File dir = LittleFS.open(path);
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
    return;
  }

  FsFile dir;
  if (!dir.open(path.c_str(), O_RDONLY)) return;
  if (!dir.isDir()) { dir.close(); return; }

  FsFile entry;
  while (entry.openNext(&dir, O_RDONLY)) {
    char name[256];
    entry.getName(name, sizeof(name));
    if (!filesystems::api::isSensitivePath(String(name))) {
      JsonObject object = out.add<JsonObject>();
      object["name"] = name;
      object["size"] = (unsigned long long)entry.fileSize();
      object["dir"] = entry.isDir();
      uint16_t date = 0, time = 0;
      if (entry.getModifyDateTime(&date, &time)) {
        uint16_t year = ((date >> 9) & 0x7F) + 1980;
        uint8_t month = (date >> 5) & 0x0F;
        uint8_t day = date & 0x1F;
        uint8_t hour = (time >> 11) & 0x1F;
        uint8_t minute = (time >> 5) & 0x3F;
        uint8_t second = (time & 0x1F) * 2;
        struct tm t = {};
        t.tm_year = year - 1900;
        t.tm_mon = month - 1;
        t.tm_mday = day;
        t.tm_hour = hour;
        t.tm_min = minute;
        t.tm_sec = second;
        object["last_write_unix"] = (unsigned long long)mktime(&t);
      }
    }
    entry.close();
  }
  dir.close();
}

bool filesystems::api::removeRecursive(FilesystemKind kind, const String &path) {
  if (kind == FilesystemKind::LittleFS) {
    File entry = LittleFS.open(path);
    if (!entry) return false;
    if (!entry.isDirectory()) {
      entry.close();
      return LittleFS.remove(path);
    }
    entry.close();
    File dir = LittleFS.open(path);
    File child = dir.openNextFile();
    while (child) {
      String child_name = String(child.name());
      bool is_directory = child.isDirectory();
      child.close();
      String child_path = (path == "/") ? "/" + child_name : path + "/" + child_name;
      if (is_directory) {
        if (!removeRecursive(kind, child_path)) { dir.close(); return false; }
      } else {
        if (!LittleFS.remove(child_path)) { dir.close(); return false; }
      }
      child = dir.openNextFile();
    }
    dir.close();
    return LittleFS.rmdir(path);
  }

  FsFile entry;
  if (!entry.open(path.c_str(), O_RDONLY)) return false;
  if (!entry.isDir()) {
    entry.close();
    return sd.remove(path.c_str());
  }
  entry.close();

  FsFile dir;
  if (!dir.open(path.c_str(), O_RDONLY)) return false;
  FsFile child;
  while (child.openNext(&dir, O_RDONLY)) {
    char name[256];
    child.getName(name, sizeof(name));
    bool is_directory = child.isDir();
    child.close();
    String child_path = (path == "/") ? "/" + String(name) : path + "/" + String(name);
    if (is_directory) {
      if (!removeRecursive(kind, child_path)) { dir.close(); return false; }
    } else {
      if (!sd.remove(child_path.c_str())) { dir.close(); return false; }
    }
  }
  dir.close();
  return sd.rmdir(path.c_str());
}
#endif

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
