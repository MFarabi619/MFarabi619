#ifndef SERVICES_SMTP_H
#define SERVICES_SMTP_H

#include "../config.h"
#include <stdint.h>
#include <stddef.h>

bool smtp_connect(void);
bool smtp_send_test_email(void);
bool smtp_get_endpoint(char *host, size_t host_len, uint16_t *port);

#endif // SERVICES_SMTP_H
