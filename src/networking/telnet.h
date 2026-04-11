#ifndef NETWORKING_TELNET_H
#define NETWORKING_TELNET_H

#include "../config.h"

void telnet_start(void);
void telnet_service(void);
bool telnet_is_connected(void);
const char *telnet_client_ip(void);
void telnet_disconnect(void);

#endif
