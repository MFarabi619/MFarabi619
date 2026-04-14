#pragma once
class AsyncWebServer;

namespace services::ws_shell {

void registerRoutes(AsyncWebServer *server);
void service(void);

}

