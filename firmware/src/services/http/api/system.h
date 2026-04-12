#pragma once

#include <ESPAsyncWebServer.h>

namespace services::http::api::system {

void registerRoutes(AsyncWebServer &server,
                    AsyncRateLimitMiddleware &reset_limit,
                    AsyncRateLimitMiddleware &ota_limit);

}
