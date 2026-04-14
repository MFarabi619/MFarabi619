#ifndef SERVICES_HTTP_H
#define SERVICES_HTTP_H

#include <stddef.h>

namespace services::http {

void initialize();
void service();
void emitEvent(const char *data, const char *event, unsigned long id);
size_t sseClientCount();
size_t sseAvgPacketsWaiting();

#ifdef PIO_UNIT_TESTING
void test();
#endif

}

#endif
