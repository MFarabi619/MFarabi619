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

void handle_solar_radiation_get(AsyncWebServerRequest *request) {
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

void handle_current_get(AsyncWebServerRequest *request) {
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

void handle_soil_get(AsyncWebServerRequest *request) {
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
    if (ok) {
      probe["temperature_celsius"] = sensor_data.temperature_celsius;
      probe["moisture_percent"] = sensor_data.moisture_percent;
      probe["conductivity"] = sensor_data.conductivity;
      probe["salinity"] = sensor_data.salinity;
      probe["tds"] = sensor_data.tds;
    }
  }

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
  server.on("/api/sensors/solar-radiation", HTTP_GET, handle_solar_radiation_get);
  server.on("/api/sensors/current", HTTP_GET, handle_current_get);
  server.on("/api/sensors/soil", HTTP_GET, handle_soil_get);

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
