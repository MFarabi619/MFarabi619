#pragma once
class AsyncWebServer;

namespace services::ws_shell {

void registerRoutes(AsyncWebServer *server);
void service(void);

#ifdef PIO_UNIT_TESTING
void test();
#endif

}

