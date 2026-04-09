#ifndef SSH_SERVER_H
#define SSH_SERVER_H

#include "../../config.h"

void ssh_server_start(void);

#ifdef PIO_UNIT_TESTING
void ssh_server_run_tests(void);
#endif

#endif // SSH_SERVER_H
