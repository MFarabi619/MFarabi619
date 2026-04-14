#ifndef SERVICES_WS_SHELL_H
#define SERVICES_WS_SHELL_H

class AsyncWebServer;

namespace services::ws_shell {

void registerRoutes(AsyncWebServer *server);
void service(void);

}

#endif
