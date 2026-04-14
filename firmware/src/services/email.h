#pragma once
#include <config.h>
#include <stdint.h>
#include <stddef.h>

namespace services::email {

bool connect();
bool sendTest();
bool accessEndpoint(char *host, size_t host_len, uint16_t *port);

#ifdef PIO_UNIT_TESTING
void test();
#endif

}

