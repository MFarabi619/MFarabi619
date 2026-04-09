#ifndef SERVICES_CLOUDEVENTS_H
#define SERVICES_CLOUDEVENTS_H

#include <ESPAsyncWebServer.h>

void cloudevents_register_routes(AsyncWebServer *server);

#ifdef PIO_UNIT_TESTING
void cloudevents_run_tests(void);
#endif

#endif // SERVICES_CLOUDEVENTS_H
