#include "api.h"
#include "sensors/routes.h"

#include <ESPAsyncWebServer.h>

void services::http::api::sensors::registerRoutes(AsyncWebServer &server) {
  co2::registerRoutes(server);
  pressure::registerRoutes(server);
  temperature_humidity::registerRoutes(server);
  wind::registerRoutes(server);
  current::registerRoutes(server);
  solar_radiation::registerRoutes(server);
  soil::registerRoutes(server);
  rainfall::registerRoutes(server);
  inventory::registerRoutes(server);
}
