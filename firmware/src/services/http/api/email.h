#pragma once

#include <ESPAsyncWebServer.h>

namespace services::http::api::email {

void registerRoutes(AsyncWebServer &server);

}
