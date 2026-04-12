#ifndef SERVICES_EMAIL_H
#define SERVICES_EMAIL_H

#include "../config.h"
#include <stdint.h>
#include <stddef.h>

namespace services::email {

bool connect() noexcept;
bool sendTest() noexcept;
[[nodiscard]] bool accessEndpoint(char *host, size_t host_len, uint16_t *port) noexcept;

#ifdef PIO_UNIT_TESTING
void test() noexcept;
#endif

}

#endif
