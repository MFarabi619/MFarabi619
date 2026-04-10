#ifndef SERVICES_WS_SHELL_H
#define SERVICES_WS_SHELL_H

#include <ESPAsyncWebServer.h>

void ws_shell_register(AsyncWebServer *server);
void ws_shell_service(void);

#endif
