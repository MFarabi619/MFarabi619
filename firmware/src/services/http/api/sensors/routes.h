#pragma once

class AsyncWebServer;

namespace services::http::api::sensors {
  namespace co2 { void registerRoutes(AsyncWebServer &server); }
  namespace pressure { void registerRoutes(AsyncWebServer &server); }
  namespace temperature_humidity { void registerRoutes(AsyncWebServer &server); }
  namespace wind { void registerRoutes(AsyncWebServer &server); }
  namespace current { void registerRoutes(AsyncWebServer &server); }
  namespace solar_radiation { void registerRoutes(AsyncWebServer &server); }
  namespace soil { void registerRoutes(AsyncWebServer &server); }
}
