#include "routes.h"
#include "../../../../sensors/carbon_dioxide.h"
#include "../../../../sensors/manager.h"

#include <ESPAsyncWebServer.h>
#include <AsyncJson.h>
#include <ArduinoJson.h>

namespace {

void handle_config_get(AsyncWebServerRequest *request) {
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

void handle_start(AsyncWebServerRequest *request) {
  bool ok = ::sensors::carbon_dioxide::enable();
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = ok;
  response->setLength();
  request->send(response);
}

void handle_stop(AsyncWebServerRequest *request) {
  bool ok = ::sensors::carbon_dioxide::disable();
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = ok;
  response->setLength();
  request->send(response);
}

}

void services::http::api::sensors::co2::registerRoutes(AsyncWebServer &server) {
  server.on("/api/co2/config", HTTP_GET, handle_config_get);
  server.on("/api/co2/start", HTTP_POST, handle_start);
  server.on("/api/co2/stop", HTTP_POST, handle_stop);

  AsyncCallbackJsonWebHandler &config_handler =
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
  config_handler.setMaxContentLength(512);
}
