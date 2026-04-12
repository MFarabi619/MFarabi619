#pragma once

#include <ESPAsyncWebServer.h>

namespace services::http::api::sensors {

void registerRoutes(AsyncWebServer &server);

}
