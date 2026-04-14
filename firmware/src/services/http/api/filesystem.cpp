#include "filesystem.h"
#include "../../../config.h"
#include "../../../filesystems/api.h"
#include "../../../hardware/storage.h"
#include "../../../programs/led.h"

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

bool ensure_parent_dirs(fs::FS &fs, const String &path) {
  int idx = 1;
  while ((idx = path.indexOf('/', idx)) > 0) {
    String dir = path.substring(0, idx);
    if (!fs.exists(dir)) fs.mkdir(dir);
    idx++;
  }
  return true;
}

bool write_with_retry(File &file, const uint8_t *data, size_t length) {
  size_t written = 0;
  uint32_t start = millis();
  while (written < length) {
    size_t n = file.write(data + written, length - written);
    if (n > 0) {
      written += n;
      start = millis();
      continue;
    }
    delay(1);
    if (millis() - start > 5000) return false;
  }
  return true;
}

void handle_legacy_files(AsyncWebServerRequest *request) {
  if (!hardware::storage::ensureSD()) {
    request->send(503, "application/json", "{\"error\":\"no SD card\"}");
    return;
  }

  AsyncJsonResponse *response = new AsyncJsonResponse(true);
  JsonArray root = response->getRoot().to<JsonArray>();
  filesystems::api::listDirectory(SD, "/", root);

  response->setLength();
  request->send(response);
}

void handle_root(AsyncWebServerRequest *request) {
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = true;

  JsonArray sd_entries = root["sd"].to<JsonArray>();
  if (hardware::storage::ensureSD()) filesystems::api::listDirectory(SD, "/", sd_entries);

  JsonArray littlefs_entries = root["littlefs"].to<JsonArray>();
  if (hardware::storage::ensureLittleFS()) filesystems::api::listDirectory(LittleFS, "/", littlefs_entries);

  response->setLength();
  request->send(response);
}

void handle_get(AsyncWebServerRequest *request) {
  FilesystemResolveCommand command = {
    .url = request->url(),
    .target = {},
  };
  filesystems::api::resolveTarget(&command);
  FilesystemTarget &target = command.target;
  if (!target.ok) {
    request->send(400, "application/json", "{\"ok\":false,\"error\":\"invalid filesystem prefix\"}");
    return;
  }
  if (filesystems::api::isSensitivePath(target.path)) {
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
    filesystems::api::listDirectory(*target.fs, target.path, root);
    response->setLength();
    request->send(response);
    return;
  }

  entry.close();
  request->send(*target.fs, target.path, "application/octet-stream");
}

void handle_mkdir(AsyncWebServerRequest *request) {
  FilesystemResolveCommand command = {
    .url = request->url(),
    .target = {},
  };
  filesystems::api::resolveTarget(&command);
  FilesystemTarget &target = command.target;
  if (!target.ok) {
    request->send(400, "application/json", "{\"ok\":false,\"error\":\"invalid filesystem prefix\"}");
    return;
  }
  if (filesystems::api::isSensitivePath(target.path)) {
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
  bool formatted = hardware::storage::ensureLittleFS() && LittleFS.format();
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

    FilesystemResolveCommand command = {
      .url = request->url(),
      .target = {},
    };
    filesystems::api::resolveTarget(&command);
    FilesystemTarget &target = command.target;
    if (!target.ok) {
      request->send(400, "application/json", "{\"ok\":false,\"error\":\"invalid filesystem prefix\"}");
      return;
    }
    if (filesystems::api::isSensitivePath(target.path)) {
      request->send(403, "application/json", "{\"ok\":false,\"error\":\"forbidden path\"}");
      return;
    }

    ensure_parent_dirs(*target.fs, target.path);

    if (target.fs->exists(target.path)) target.fs->remove(target.path);

    request->_tempFile = target.fs->open(target.path, FILE_WRITE, true);
    if (!request->_tempFile) {
      request->send(500, "application/json", "{\"ok\":false,\"error\":\"open failed\"}");
      return;
    }

    state->ok = true;
    Serial.printf("[http] upload: %s\n", target.path.c_str());
  }

  if (request->getResponse()) return;

  if (state && state->ok) {
    float t = (float)(millis() % 1000) / 1000.0f;
    uint8_t b = (uint8_t)((sinf(t * 6.2832f) + 1.0f) * 0.5f * 200.0f) + 10;
    LED.setBrightness(b);
    LED.set(CRGB::White);
  }

  if (state && state->ok && request->_tempFile && len) {
    if (!write_with_retry(request->_tempFile, data, len)) {
      state->ok = false;
      request->_tempFile.close();
      request->abort();
    }
  }

  if (final) {
    if (request->_tempFile) request->_tempFile.close();
    if (state && state->ok) {
      Serial.printf("[http] upload complete (%u bytes)\n", (unsigned)(index + len));
    }
    LED.setBrightness(config::led::BRIGHTNESS);
    LED.set(CRGB::Green);
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
  FilesystemResolveCommand command = {
    .url = request->url(),
    .target = {},
  };
  filesystems::api::resolveTarget(&command);
  FilesystemTarget &target = command.target;
  if (!target.ok) {
    request->send(400, "application/json", "{\"ok\":false,\"error\":\"invalid filesystem prefix\"}");
    return;
  }
  if (filesystems::api::isSensitivePath(target.path)) {
    request->send(403, "application/json", "{\"ok\":false,\"error\":\"forbidden path\"}");
    return;
  }

  bool removed = filesystems::api::removeRecursive(*target.fs, target.path);
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
    FilesystemResolveCommand command = {
      .url = request->url(),
      .target = {},
    };
    filesystems::api::resolveTarget(&command);
    FilesystemTarget &target = command.target;
    if (!target.ok) {
      request->send(400, "application/json", "{\"ok\":false,\"error\":\"invalid filesystem prefix\"}");
      return;
    }
    if (filesystems::api::isSensitivePath(target.path)) {
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

    if (filesystems::api::isSensitivePath(new_path)) {
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
