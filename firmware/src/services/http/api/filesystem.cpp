#include "filesystem.h"
#include "../../../config.h"

#include <Arduino.h>
#include <AsyncJson.h>
#include <ArduinoJson.h>
#include <LittleFS.h>
#include <SD.h>

#include <memory>

namespace {

struct FileUploadState {
  bool ok = false;
};

struct FilesystemTarget {
  fs::FS *fs;
  String path;
  bool ok;
};

bool sd_ready = false;

bool is_sensitive_path(const String &path) {
  return path == "/.ssh" || path.startsWith("/.ssh/")
      || path == config::ssh::HOSTKEY_PATH;
}

bool ensure_sd(void) {
  if (sd_ready) return true;
  sd_ready = SD.begin();
  return sd_ready;
}

FilesystemTarget resolve_filesystem_target(const String &url) {
  const char *prefix = "/api/filesystem/";
  String remainder = url.substring(strlen(prefix));

  if (remainder.startsWith("sd")) {
    String path = remainder.substring(2);
    if (path.isEmpty()) path = "/";
    if (ensure_sd()) return {&SD, path, true};
    return {nullptr, path, false};
  }

  if (remainder.startsWith("littlefs")) {
    String path = remainder.substring(8);
    if (path.isEmpty()) path = "/";
    return {&LittleFS, path, true};
  }

  return {nullptr, "", false};
}

void list_directory(fs::FS &filesystem, const String &path, JsonArray &out) {
  File dir = filesystem.open(path);
  if (!dir || !dir.isDirectory()) return;

  File entry = dir.openNextFile();
  while (entry) {
    String name = String(entry.name());
    if (!is_sensitive_path(name)) {
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

bool recursive_delete(fs::FS &filesystem, const String &path) {
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
      if (!recursive_delete(filesystem, child_path)) {
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

void handle_legacy_files(AsyncWebServerRequest *request) {
  if (!ensure_sd()) {
    request->send(503, "application/json", "{\"error\":\"no SD card\"}");
    return;
  }

  AsyncJsonResponse *response = new AsyncJsonResponse(true);
  JsonArray root = response->getRoot().to<JsonArray>();
  list_directory(SD, "/", root);

  response->setLength();
  request->send(response);
}

void handle_root(AsyncWebServerRequest *request) {
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = true;

  JsonArray sd_entries = root["sd"].to<JsonArray>();
  if (ensure_sd()) list_directory(SD, "/", sd_entries);

  JsonArray littlefs_entries = root["littlefs"].to<JsonArray>();
  list_directory(LittleFS, "/", littlefs_entries);

  response->setLength();
  request->send(response);
}

void handle_get(AsyncWebServerRequest *request) {
  FilesystemTarget target = resolve_filesystem_target(request->url());
  if (!target.ok) {
    request->send(400, "application/json", "{\"ok\":false,\"error\":\"invalid filesystem prefix\"}");
    return;
  }
  if (is_sensitive_path(target.path)) {
    request->send(403, "application/json", "{\"ok\":false,\"error\":\"forbidden path\"}");
    return;
  }

  File entry = target.fs->open(target.path);
  if (!entry) {
    request->send(404, "application/json", "{\"ok\":false,\"error\":\"not found\"}");
    return;
  }

  if (entry.isDirectory()) {
    entry.close();
    AsyncJsonResponse *response = new AsyncJsonResponse(true);
    JsonArray root = response->getRoot().to<JsonArray>();
    list_directory(*target.fs, target.path, root);
    response->setLength();
    request->send(response);
    return;
  }

  entry.close();
  request->send(*target.fs, target.path, "application/octet-stream");
}

void handle_mkdir(AsyncWebServerRequest *request) {
  FilesystemTarget target = resolve_filesystem_target(request->url());
  if (!target.ok) {
    request->send(400, "application/json", "{\"ok\":false,\"error\":\"invalid filesystem prefix\"}");
    return;
  }
  if (is_sensitive_path(target.path)) {
    request->send(403, "application/json", "{\"ok\":false,\"error\":\"forbidden path\"}");
    return;
  }

  bool created = target.fs->mkdir(target.path);
  AsyncJsonResponse *response = new AsyncJsonResponse();
  response->setCode(created ? 201 : 500);
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = created;
  response->setLength();
  request->send(response);
}

void handle_format(AsyncWebServerRequest *request) {
  bool formatted = LittleFS.format();
  AsyncJsonResponse *response = new AsyncJsonResponse();
  response->setCode(formatted ? 200 : 500);
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = formatted;
  response->setLength();
  request->send(response);
}

void handle_upload(AsyncWebServerRequest *request, String filename,
                   size_t index, uint8_t *data, size_t len, bool final) {
  (void)filename;
  FileUploadState *state = reinterpret_cast<FileUploadState *>(request->_tempObject);

  if (!index) {
    delete state;
    state = new FileUploadState();
    request->_tempObject = state;

    FilesystemTarget target = resolve_filesystem_target(request->url());
    if (!target.ok) {
      request->send(400, "application/json", "{\"ok\":false,\"error\":\"invalid filesystem prefix\"}");
      return;
    }
    if (is_sensitive_path(target.path)) {
      request->send(403, "application/json", "{\"ok\":false,\"error\":\"forbidden path\"}");
      return;
    }

    request->_tempFile = target.fs->open(target.path, FILE_WRITE, true);
    if (!request->_tempFile) {
      request->send(500, "application/json", "{\"ok\":false,\"error\":\"open failed\"}");
      return;
    }

    state->ok = true;
    Serial.printf("[http] upload: %s\n", target.path.c_str());
  }

  if (request->getResponse()) return;

  if (state && state->ok && request->_tempFile && len) {
    if (request->_tempFile.write(data, len) != len) {
      state->ok = false;
      request->send(500, "application/json", "{\"ok\":false,\"error\":\"write failed\"}");
    }
  }

  if (final) {
    if (request->_tempFile) request->_tempFile.close();
    if (state && state->ok) {
      Serial.printf("[http] upload complete (%u bytes)\n", (unsigned)(index + len));
    }
  }
}

void handle_upload_complete(AsyncWebServerRequest *request) {
  std::unique_ptr<FileUploadState> state(
      reinterpret_cast<FileUploadState *>(request->_tempObject));
  request->_tempObject = nullptr;

  if (request->getResponse()) return;

  AsyncJsonResponse *response = new AsyncJsonResponse();
  response->setCode((state && state->ok) ? 201 : 500);
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = (state && state->ok);
  response->setLength();
  request->send(response);
}

void handle_delete(AsyncWebServerRequest *request) {
  FilesystemTarget target = resolve_filesystem_target(request->url());
  if (!target.ok) {
    request->send(400, "application/json", "{\"ok\":false,\"error\":\"invalid filesystem prefix\"}");
    return;
  }
  if (is_sensitive_path(target.path)) {
    request->send(403, "application/json", "{\"ok\":false,\"error\":\"forbidden path\"}");
    return;
  }

  bool removed = recursive_delete(*target.fs, target.path);
  AsyncJsonResponse *response = new AsyncJsonResponse();
  response->setCode(removed ? 200 : 404);
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = removed;
  response->setLength();
  request->send(response);
}

}

void services::http::api::filesystem::registerRoutes(AsyncWebServer &server,
                                                     AsyncRateLimitMiddleware &format_limit) {
  server.on("/api/files", HTTP_GET, handle_legacy_files);

  server.on(AsyncURIMatcher::exact("/api/filesystem"), HTTP_GET, handle_root);
  server.on("/api/filesystem/littlefs/format", HTTP_POST, handle_format)
    .addMiddleware(&format_limit);
  server.on(AsyncURIMatcher::dir("/api/filesystem"), HTTP_GET, handle_get);
  server.on(AsyncURIMatcher::dir("/api/filesystem"), HTTP_POST, handle_mkdir);
  server.on(AsyncURIMatcher::dir("/api/filesystem"), HTTP_PUT,
            handle_upload_complete, handle_upload);
  server.on(AsyncURIMatcher::dir("/api/filesystem"), HTTP_DELETE, handle_delete);

  AsyncCallbackJsonWebHandler &rename_handler =
      server.on(AsyncURIMatcher::dir("/api/filesystem"), HTTP_PATCH,
          [](AsyncWebServerRequest *request, JsonVariant &json) {
    FilesystemTarget target = resolve_filesystem_target(request->url());
    if (!target.ok) {
      request->send(400, "application/json", "{\"ok\":false,\"error\":\"invalid filesystem prefix\"}");
      return;
    }
    if (is_sensitive_path(target.path)) {
      request->send(403, "application/json", "{\"ok\":false,\"error\":\"forbidden path\"}");
      return;
    }

    JsonObject body = json.as<JsonObject>();
    String new_name = body["name"] | "";
    if (new_name.isEmpty()) {
      request->send(400, "application/json", "{\"ok\":false,\"error\":\"missing name in body\"}");
      return;
    }

    int last_slash = target.path.lastIndexOf('/');
    String dir = (last_slash > 0) ? target.path.substring(0, last_slash) : "";
    String new_path = dir + "/" + new_name;

    if (is_sensitive_path(new_path)) {
      request->send(403, "application/json", "{\"ok\":false,\"error\":\"forbidden path\"}");
      return;
    }

    bool ok = target.fs->rename(target.path, new_path);
    AsyncJsonResponse *response = new AsyncJsonResponse();
    response->setCode(ok ? 200 : 500);
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = ok;
    if (ok) {
      root["from"] = target.path;
      root["to"] = new_path;
    }
    response->setLength();
    request->send(response);
  });
  rename_handler.setMaxContentLength(256);
}
