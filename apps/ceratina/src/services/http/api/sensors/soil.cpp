#include "routes.h"
#include <manager.h>

#include <ESPAsyncWebServer.h>
#include <AsyncJson.h>
#include <ArduinoJson.h>

namespace {

void handle_get(AsyncWebServerRequest *request) {
  SensorInventorySnapshot inventory = {};
  sensors::manager::accessInventory(&inventory);

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = inventory.soil_probe_count > 0;
  JsonObject data = root["data"].to<JsonObject>();
  data["probe_count"] = inventory.soil_probe_count;

  JsonArray probes = data["probes"].to<JsonArray>();
  for (uint8_t index = 0; index < inventory.soil_probe_count; index++) {
    SoilSensorData sensor_data = {};
    bool ok = sensors::manager::accessSoil(index, &sensor_data);

    JsonObject probe = probes.add<JsonObject>();
    probe["index"] = index;
    probe["slave_id"] = sensor_data.slave_id;
    probe["read_ok"] = ok;
    probe["has_ph"] = sensor_data.has_ph;
    if (ok) {
      probe["temperature_celsius"] = sensor_data.temperature_celsius;
      probe["moisture_percent"] = sensor_data.moisture_percent;
      probe["conductivity"] = sensor_data.conductivity;
      probe["salinity"] = sensor_data.salinity;
      probe["tds"] = sensor_data.tds;
      if (sensor_data.has_ph) probe["ph"] = sensor_data.ph;
    }
  }

  response->setLength();
  request->send(response);
}

}

void services::http::api::sensors::soil::registerRoutes(AsyncWebServer &server) {
  server.on("/api/sensors/soil", HTTP_GET, handle_get);
}
