#pragma once

#include <ESPAsyncWebServer.h>

namespace services::http::api::filesystem {

void registerRoutes(AsyncWebServer &server,
                    AsyncRateLimitMiddleware &format_limit);

}
