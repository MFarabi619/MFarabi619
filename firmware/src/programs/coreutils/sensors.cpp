#include "sensors.h"

#include "../../sensors/manager.h"

namespace {

void exec(struct ush_object *self,
          struct ush_file_descriptor const *file,
          int argc, char *argv[]) {
  (void)file;
  (void)argv;
  if (argc != 1) {
    ush_print_status(self, USH_STATUS_ERROR_COMMAND_WRONG_ARGUMENTS);
    return;
  }

  SensorInventorySnapshot inventory = {};
  sensors::manager::accessInventory(&inventory);

  TemperatureHumiditySensorData temperature_humidity[config::temperature_humidity::MAX_SENSORS] = {};
  WindSpeedSensorData wind_speed = {};
  WindDirectionSensorData wind_direction = {};
  uint8_t temperature_humidity_ok = 0;
  for (uint8_t index = 0; index < inventory.temperature_humidity_count; index++) {
    if (sensors::manager::accessTemperatureHumidity(index, &temperature_humidity[index])) {
      temperature_humidity_ok++;
    }
  }
  bool wind_speed_ok = sensors::manager::accessWindSpeed(&wind_speed);
  bool wind_direction_ok = sensors::manager::accessWindDirection(&wind_direction);

  ush_printf(self,
             "temperature_humidity=%u\r\n"
             "voltage=%s\r\n"
             "current=%s\r\n"
             "carbon_dioxide=%s\r\n"
             "wind_speed=%s",
             inventory.temperature_humidity_count,
             inventory.voltage_available ? "available" : "unavailable",
             inventory.current_available ? "available" : "unavailable",
             inventory.carbon_dioxide_available ? "available" : "unavailable",
             inventory.wind_speed_available ? "available" : "unavailable");
  if (temperature_humidity_ok > 0) {
    for (uint8_t index = 0; index < inventory.temperature_humidity_count; index++) {
      if (!temperature_humidity[index].ok) continue;
      ush_printf(self, "temperature_humidity[%u]=%s %.2f C %.2f %% RH\r\n",
                 index,
                 temperature_humidity[index].model ? temperature_humidity[index].model : "unknown",
                 temperature_humidity[index].temperature_celsius,
                 temperature_humidity[index].relative_humidity_percent);
    }
  }
  if (wind_speed_ok) {
    ush_printf(self, " (%.2f km/h)\r\n", wind_speed.kilometers_per_hour);
  } else {
    ush_print(self, (char *)"\r\n");
  }

  ush_printf(self, "wind_direction=%s",
             inventory.wind_direction_available ? "available" : "unavailable");
  if (wind_direction_ok) {
    ush_printf(self, " (%.1f deg, slice=%u)\r\n",
               wind_direction.degrees, wind_direction.slice);
  } else {
    ush_print(self, (char *)"\r\n");
  }

  ush_printf(self, "solar_radiation=%s",
             inventory.solar_radiation_available ? "available" : "unavailable");
  SolarRadiationSensorData solar = {};
  if (sensors::manager::accessSolarRadiation(&solar) && solar.ok) {
    ush_printf(self, " (%u W/m2)\r\n", solar.watts_per_square_meter);
  } else {
    ush_print(self, (char *)"\r\n");
  }

  CurrentSensorData current = {};
  bool current_ok = sensors::manager::accessCurrent(&current);
  ush_printf(self, "current=%s",
             inventory.current_available ? "available" : "unavailable");
  if (current_ok && current.ok) {
    ush_printf(self, " (%.2f mA, %.3f V, %.2f mW)\r\n",
               current.current_mA, current.bus_voltage_V, current.power_mW);
  } else {
    ush_print(self, (char *)"\r\n");
  }

  ush_printf(self, "soil_probes=%u\r\n", inventory.soil_probe_count);
  for (uint8_t index = 0; index < inventory.soil_probe_count; index++) {
    SoilSensorData soil = {};
    if (sensors::manager::accessSoil(index, &soil) && soil.ok) {
      ush_printf(self, "soil[%u] slave=%u %.1f C %.1f%% EC=%u TDS=%u\r\n",
                 index, soil.slave_id,
                 soil.temperature_celsius, soil.moisture_percent,
                 soil.conductivity, soil.tds);
    }
  }
}

}

const struct ush_file_descriptor programs::coreutils::sensors::descriptor = {
  .name = "sensors",
  .description = "show sensor inventory summary",
  .help = "usage: sensors\r\n",
  .exec = exec,
};
