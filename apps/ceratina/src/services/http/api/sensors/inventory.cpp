#include "routes.h"
#include <manager.h>

#include <ESPAsyncWebServer.h>
#include <AsyncJson.h>
#include <ArduinoJson.h>

namespace {

void handle_get(AsyncWebServerRequest *request) {
  SensorInventorySnapshot snapshot = {};
  sensors::manager::accessInventory(&snapshot);

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = true;

  JsonObject data = root["data"].to<JsonObject>();
  data["temperature_humidity_count"] = snapshot.temperature_humidity_count;
  data["soil_probe_count"] = snapshot.soil_probe_count;
  data["voltage_available"] = snapshot.voltage_available;
  data["current_available"] = snapshot.current_available;
  data["co2_available"] = snapshot.carbon_dioxide_available;
  data["wind_speed_available"] = snapshot.wind_speed_available;
  data["wind_direction_available"] = snapshot.wind_direction_available;
  data["solar_radiation_available"] = snapshot.solar_radiation_available;
  data["barometric_pressure_available"] = snapshot.barometric_pressure_available;

  response->setLength();
  request->send(response);
}

}

void services::http::api::sensors::inventory::registerRoutes(AsyncWebServer &server) {
  server.on("/api/sensors/inventory", HTTP_GET, handle_get);
}