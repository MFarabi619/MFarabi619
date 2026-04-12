#ifndef SERVICES_HTTP_H
#define SERVICES_HTTP_H

#include "../config.h"
#include <ESPAsyncWebServer.h>

extern AsyncEventSource http_events;

namespace services::http {

void initialize();
void service();

#ifdef PIO_UNIT_TESTING
void test();
#endif

}

#endif // SERVICES_HTTP_H
