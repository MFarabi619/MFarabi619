#pragma once

#include <ESPAsyncWebServer.h>

namespace services::http::api::networking {

void registerRoutes(AsyncWebServer &server,
                    AsyncRateLimitMiddleware &scan_limit);

}
