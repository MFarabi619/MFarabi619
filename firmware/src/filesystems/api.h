#ifndef FILESYSTEMS_API_H
#define FILESYSTEMS_API_H

#include "../config.h"
#include <Arduino.h>
#include <ArduinoJson.h>
#include <FS.h>

#if 0
// Temporarily disabled while reverting to Arduino SD.h.
enum class FilesystemKind : uint8_t { SD, LittleFS };

struct FilesystemTarget {
  FilesystemKind kind;
  String path;
  bool ok;
};

struct FilesystemResolveCommand {
  String url;
  FilesystemTarget target;
};

namespace filesystems::api {

bool isSensitivePath(const String &path);
bool resolveTarget(FilesystemResolveCommand *command);
void listDirectory(FilesystemKind kind, const String &path, JsonArray &out);
bool removeRecursive(FilesystemKind kind, const String &path);
#endif

struct FilesystemTarget {
  fs::FS *fs;
  String path;
  bool ok;
};

struct FilesystemResolveCommand {
  String url;
  FilesystemTarget target;
};

namespace filesystems::api {

bool isSensitivePath(const String &path);
bool resolveTarget(FilesystemResolveCommand *command);
void listDirectory(fs::FS &filesystem, const String &path, JsonArray &out);
bool removeRecursive(fs::FS &filesystem, const String &path);

}

#endif
