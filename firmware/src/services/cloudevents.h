#pragma once
class AsyncWebServer;

namespace services::cloudevents {

void registerRoutes(AsyncWebServer *server);

#ifdef PIO_UNIT_TESTING
void test(void);
#endif

}

