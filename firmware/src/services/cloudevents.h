#ifndef SERVICES_CLOUDEVENTS_H
#define SERVICES_CLOUDEVENTS_H

class AsyncWebServer;

namespace services::cloudevents {

void registerRoutes(AsyncWebServer *server);

#ifdef PIO_UNIT_TESTING
void test(void);
#endif

}

#endif
