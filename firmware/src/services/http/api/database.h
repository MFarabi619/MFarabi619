#pragma once

#include <ESPAsyncWebServer.h>

namespace services::http::api::database {

void registerRoutes(AsyncWebServer &server);

#ifdef PIO_UNIT_TESTING
void test();
#endif

}
