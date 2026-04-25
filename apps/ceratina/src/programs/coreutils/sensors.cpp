#include "coreutils.h"
#include <manager.h>
#include <config.h>

#include <stdio.h>

int programs::coreutils::cmd_sensors(int argc, char **argv) {
  (void)argv;
  if (argc != 1) { printf("usage: sensors\n"); return 1; }

  SensorInventorySnapshot inventory = {};
  sensors::manager::accessInventory(&inventory);

  TemperatureHumiditySensorData temperature_humidity[config::temperature_humidity::MAX_SENSORS] = {};
  WindSpeedSensorData wind_speed = {};
  WindDirectionSensorData wind_direction = {};
  uint8_t temperature_humidity_ok = 0;
  for (uint8_t index = 0; index < inventory.temperature_humidity_count; index++) {
    if (sensors::manager::accessTemperatureHumidity(index, &temperature_humidity[index]))
      temperature_humidity_ok++;
  }
  bool wind_speed_ok = sensors::manager::accessWindSpeed(&wind_speed);
  bool wind_direction_ok = sensors::manager::accessWindDirection(&wind_direction);

  printf("temperature_humidity=%u\n"
         "voltage=%s\n"
         "current=%s\n"
         "carbon_dioxide=%s\n"
         "wind_speed=%s",
         inventory.temperature_humidity_count,
         inventory.voltage_available ? "available" : "unavailable",
         inventory.current_available ? "available" : "unavailable",
         inventory.carbon_dioxide_available ? "available" : "unavailable",
         inventory.wind_speed_available ? "available" : "unavailable");

  if (temperature_humidity_ok > 0) {
    for (uint8_t index = 0; index < inventory.temperature_humidity_count; index++) {
      if (!temperature_humidity[index].ok) continue;
      printf("temperature_humidity[%u]=%s %.2f C %.2f %% RH\n",
             index,
             temperature_humidity[index].model ? temperature_humidity[index].model : "unknown",
             temperature_humidity[index].temperature_celsius,
             temperature_humidity[index].relative_humidity_percent);
    }
  }

  if (wind_speed_ok)
    printf(" (%.2f km/h)\n", wind_speed.kilometers_per_hour);
  else
    printf("\n");

  printf("wind_direction=%s",
         inventory.wind_direction_available ? "available" : "unavailable");
  if (wind_direction_ok)
    printf(" (%.1f deg, slice=%u)\n", wind_direction.degrees, wind_direction.slice);
  else
    printf("\n");

  printf("solar_radiation=%s",
         inventory.solar_radiation_available ? "available" : "unavailable");
  SolarRadiationSensorData solar = {};
  if (sensors::manager::accessSolarRadiation(&solar) && solar.ok)
    printf(" (%u W/m2)\n", solar.watts_per_square_meter);
  else
    printf("\n");

  CurrentSensorData current = {};
  bool current_ok = sensors::manager::accessCurrent(&current);
  printf("current=%s",
         inventory.current_available ? "available" : "unavailable");
  if (current_ok && current.ok)
    printf(" (%.2f mA, %.3f V, %.2f mW)\n",
           current.current_mA, current.bus_voltage_V, current.power_mW);
  else
    printf("\n");

  printf("soil_probes=%u\n", inventory.soil_probe_count);
  for (uint8_t index = 0; index < inventory.soil_probe_count; index++) {
    SoilSensorData soil = {};
    if (sensors::manager::accessSoil(index, &soil) && soil.ok) {
      printf("soil[%u] slave=%u %.1f C %.1f%% EC=%u TDS=%u",
             index, soil.slave_id,
             soil.temperature_celsius, soil.moisture_percent,
             soil.conductivity, soil.tds);
      if (soil.has_ph) printf(" pH=%.1f", soil.ph);
      printf("\n");
    }
  }

  return 0;
}
