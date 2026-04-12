#ifndef SERVICES_CLOUDEVENTS_H
#define SERVICES_CLOUDEVENTS_H

#include <ESPAsyncWebServer.h>

namespace services::cloudevents {

void registerRoutes(AsyncWebServer *server);

#ifdef PIO_UNIT_TESTING
void test(void);
#endif

}

#endif // SERVICES_CLOUDEVENTS_H
