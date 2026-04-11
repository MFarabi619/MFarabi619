#ifndef SERVICES_HTTP_H
#define SERVICES_HTTP_H

#include "../config.h"
#include <ESPAsyncWebServer.h>

void http_server_start(void);
void http_server_service(void);

// SSE event source — call events.send() to push data to connected browsers
extern AsyncEventSource http_events;

#endif // SERVICES_HTTP_H
