#include "routes.h"
#include "../../../../sensors/manager.h"

#include <ESPAsyncWebServer.h>
#include <AsyncJson.h>
#include <ArduinoJson.h>

namespace {

void handle_speed_get(AsyncWebServerRequest *request) {
  WindSpeedSensorData sensor_data = {};
  bool ok = sensors::manager::accessWindSpeed(&sensor_data);

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = ok && sensor_data.ok;
  JsonObject data = root["data"].to<JsonObject>();
  if (ok && sensor_data.ok) {
    data["wind_speed_kilometers_per_hour"] = sensor_data.kilometers_per_hour;
  }
  response->setLength();
  request->send(response);
}

void handle_direction_get(AsyncWebServerRequest *request) {
  WindDirectionSensorData sensor_data = {};
  bool ok = sensors::manager::accessWindDirection(&sensor_data);

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = ok && sensor_data.ok;
  JsonObject data = root["data"].to<JsonObject>();
  if (ok && sensor_data.ok) {
    data["wind_direction_degrees"] = sensor_data.degrees;
    data["wind_direction_angle_slice"] = sensor_data.slice;
  }
  response->setLength();
  request->send(response);
}

}

void services::http::api::sensors::wind::registerRoutes(AsyncWebServer &server) {
  server.on("/api/sensors/wind/speed", HTTP_GET, handle_speed_get);
  server.on("/api/sensors/wind/direction", HTTP_GET, handle_direction_get);
}
