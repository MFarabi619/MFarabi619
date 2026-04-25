#include "routes.h"
#include <manager.h>

#include <ESPAsyncWebServer.h>
#include <AsyncJson.h>
#include <ArduinoJson.h>

namespace {

void handle_get(AsyncWebServerRequest *request) {
  RainfallSensorData sensor_data = {};
  bool ok = sensors::manager::accessRainfall(&sensor_data);

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = ok && sensor_data.ok;
  JsonObject data = root["data"].to<JsonObject>();
  if (ok && sensor_data.ok) {
    data["rainfall_millimeters"] = sensor_data.millimeters;
  }
  response->setLength();
  request->send(response);
}

}

void services::http::api::sensors::rainfall::registerRoutes(AsyncWebServer &server) {
  server.on("/api/sensors/rainfall", HTTP_GET, handle_get);
}
