#ifndef SERVICES_WS_SHELL_H
#define SERVICES_WS_SHELL_H

#include <ESPAsyncWebServer.h>

namespace services::ws_shell {

void registerRoutes(AsyncWebServer *server);
void service(void);

}

#endif
