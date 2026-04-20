#pragma once
#include <config.h>
#include <Arduino.h>
#include <ArduinoJson.h>
#include <FS.h>

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

#ifdef PIO_UNIT_TESTING
void test();
#endif

}

