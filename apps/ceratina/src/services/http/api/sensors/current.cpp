#include "routes.h"
#include <manager.h>

#include <ESPAsyncWebServer.h>
#include <AsyncJson.h>
#include <ArduinoJson.h>

namespace {

void handle_get(AsyncWebServerRequest *request) {
  CurrentSensorData sensor_data = {};
  bool ok = sensors::manager::accessCurrent(&sensor_data);

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = ok && sensor_data.ok;
  JsonObject data = root["data"].to<JsonObject>();
  if (ok && sensor_data.ok) {
    data["current_mA"] = sensor_data.current_mA;
    data["bus_voltage_V"] = sensor_data.bus_voltage_V;
    data["shunt_voltage_mV"] = sensor_data.shunt_voltage_mV;
    data["power_mW"] = sensor_data.power_mW;
    data["energy_J"] = sensor_data.energy_J;
    data["charge_C"] = sensor_data.charge_C;
    data["die_temperature_C"] = sensor_data.die_temperature_C;
  }
  response->setLength();
  request->send(response);
}

}

void services::http::api::sensors::current::registerRoutes(AsyncWebServer &server) {
  server.on("/api/sensors/current", HTTP_GET, handle_get);
}
