#include "routes.h"
#include <manager.h>

#include <ESPAsyncWebServer.h>
#include <AsyncJson.h>
#include <ArduinoJson.h>

namespace {

void handle_get(AsyncWebServerRequest *request) {
  BarometricPressureSensorData sensor_data = {};
  bool ok = sensors::manager::accessBarometricPressure(&sensor_data);

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = ok && sensor_data.ok;
  JsonObject data = root["data"].to<JsonObject>();
  if (ok && sensor_data.ok) {
    data["pressure_hpa"] = sensor_data.pressure_hpa;
    data["temperature_celsius"] = sensor_data.temperature_celsius;
    data["model"] = sensor_data.model;
  }
  response->setLength();
  request->send(response);
}

}

void services::http::api::sensors::pressure::registerRoutes(AsyncWebServer &server) {
  server.on("/api/sensors/pressure", HTTP_GET, handle_get);
}
