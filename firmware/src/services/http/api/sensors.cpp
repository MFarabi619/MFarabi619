#include "sensors.h"
#include "../../../sensors/carbon_dioxide.h"
#include "../../../sensors/manager.h"

#include <AsyncJson.h>
#include <ArduinoJson.h>

namespace {

void handle_co2_config_get(AsyncWebServerRequest *request) {
  Co2Config config = {};
  ::sensors::carbon_dioxide::accessConfig(&config);

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = ::sensors::carbon_dioxide::isAvailable();
  JsonObject data = root["data"].to<JsonObject>();
  data["model"] = config.model;
  data["measuring"] = config.measuring;
  data["measurement_interval_seconds"] = config.measurement_interval_seconds;
  data["auto_calibration_enabled"] = config.auto_calibration_enabled;
  data["temperature_offset_celsius"] = config.temperature_offset_celsius;
  data["altitude_meters"] = config.altitude_meters;
  response->setLength();
  request->send(response);
}

void handle_co2_start(AsyncWebServerRequest *request) {
  bool ok = ::sensors::carbon_dioxide::enable();
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = ok;
  response->setLength();
  request->send(response);
}

void handle_co2_stop(AsyncWebServerRequest *request) {
  bool ok = ::sensors::carbon_dioxide::disable();
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = ok;
  response->setLength();
  request->send(response);
}

void handle_wind_speed_get(AsyncWebServerRequest *request) {
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

void handle_wind_direction_get(AsyncWebServerRequest *request) {
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

void handle_temperature_humidity_get(AsyncWebServerRequest *request) {
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

void services::http::api::sensors::registerRoutes(AsyncWebServer &server) {
  server.on("/api/co2/config", HTTP_GET, handle_co2_config_get);
  server.on("/api/co2/start", HTTP_POST, handle_co2_start);
  server.on("/api/co2/stop", HTTP_POST, handle_co2_stop);
  server.on("/api/sensors/temperature-humidity", HTTP_GET, handle_temperature_humidity_get);
  server.on("/api/sensors/wind/speed", HTTP_GET, handle_wind_speed_get);
  server.on("/api/sensors/wind/direction", HTTP_GET, handle_wind_direction_get);

  AsyncCallbackJsonWebHandler &co2_config_handler =
      server.on("/api/co2/config", HTTP_POST,
          [](AsyncWebServerRequest *request, JsonVariant &json) {
    JsonObject body = json.as<JsonObject>();
    if (!body["measurement_interval_seconds"].isNull())
      ::sensors::carbon_dioxide::configureInterval(body["measurement_interval_seconds"]);
    if (!body["auto_calibration_enabled"].isNull())
      ::sensors::carbon_dioxide::configureAutoCalibration(body["auto_calibration_enabled"]);
    if (!body["temperature_offset_celsius"].isNull())
      ::sensors::carbon_dioxide::configureTemperatureOffset(body["temperature_offset_celsius"]);
    if (!body["altitude_meters"].isNull())
      ::sensors::carbon_dioxide::configureAltitude(body["altitude_meters"]);
    if (!body["forced_recalibration_ppm"].isNull())
      ::sensors::carbon_dioxide::configureRecalibration(body["forced_recalibration_ppm"]);

    Co2Config config = {};
    ::sensors::carbon_dioxide::accessConfig(&config);
    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = ::sensors::carbon_dioxide::isAvailable();
    JsonObject data = root["data"].to<JsonObject>();
    data["model"] = config.model;
    data["measuring"] = config.measuring;
    data["measurement_interval_seconds"] = config.measurement_interval_seconds;
    data["auto_calibration_enabled"] = config.auto_calibration_enabled;
    data["temperature_offset_celsius"] = config.temperature_offset_celsius;
    data["altitude_meters"] = config.altitude_meters;
    response->setLength();
    request->send(response);
  });
  co2_config_handler.setMaxContentLength(512);
}
