#include "routes.h"
#include "../../../../sensors/manager.h"

#include <ESPAsyncWebServer.h>
#include <AsyncJson.h>
#include <ArduinoJson.h>

namespace {

void handle_get(AsyncWebServerRequest *request) {
  SensorInventorySnapshot inventory = {};
  sensors::manager::accessInventory(&inventory);

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  JsonObject data = root["data"].to<JsonObject>();
  root["ok"] = inventory.temperature_humidity_count > 0;
  data["sensor_count"] = inventory.temperature_humidity_count;

  JsonArray sensors_json = data["sensors"].to<JsonArray>();
  uint16_t successful_reads = 0;
  for (uint8_t index = 0; index < inventory.temperature_humidity_count; index++) {
    TemperatureHumiditySensorData sensor_data = {};
    bool ok = sensors::manager::accessTemperatureHumidity(index, &sensor_data);

    JsonObject sensor = sensors_json.add<JsonObject>();
    sensor["index"] = index;
    sensor["read_ok"] = ok;
    if (ok) {
      sensor["model"] = sensor_data.model ? sensor_data.model : "unknown";
      sensor["temperature_celsius"] = sensor_data.temperature_celsius;
      sensor["relative_humidity_percent"] = sensor_data.relative_humidity_percent;
      successful_reads++;
    }
  }

  data["successful_reads"] = successful_reads;
  response->setLength();
  request->send(response);
}

}

void services::http::api::sensors::temperature_humidity::registerRoutes(AsyncWebServer &server) {
  server.on("/api/sensors/temperature-humidity", HTTP_GET, handle_get);
}
