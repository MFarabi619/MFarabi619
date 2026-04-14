#include "routes.h"
#include "../../../../sensors/manager.h"

#include <ESPAsyncWebServer.h>
#include <AsyncJson.h>
#include <ArduinoJson.h>

namespace {

void handle_get(AsyncWebServerRequest *request) {
  SolarRadiationSensorData sensor_data = {};
  bool ok = sensors::manager::accessSolarRadiation(&sensor_data);

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = ok && sensor_data.ok;
  JsonObject data = root["data"].to<JsonObject>();
  if (ok && sensor_data.ok) {
    data["watts_per_square_meter"] = sensor_data.watts_per_square_meter;
  }
  response->setLength();
  request->send(response);
}

}

void services::http::api::sensors::solar_radiation::registerRoutes(AsyncWebServer &server) {
  server.on("/api/sensors/solar-radiation", HTTP_GET, handle_get);
}
