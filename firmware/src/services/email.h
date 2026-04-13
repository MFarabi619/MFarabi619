#ifndef SERVICES_EMAIL_H
#define SERVICES_EMAIL_H

#include "../config.h"
#include <stdint.h>
#include <stddef.h>

namespace services::email {

bool connect();
bool sendTest();
[[nodiscard]] bool accessEndpoint(char *host, size_t host_len, uint16_t *port);

#ifdef PIO_UNIT_TESTING
void test();
#endif

}

#endif
