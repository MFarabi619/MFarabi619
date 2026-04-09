#ifndef SSH_SERVER_H
#define SSH_SERVER_H

#include "../../config.h"

bool ssh_server_start(void);

struct ush_object;
bool ssh_server_request_exit(struct ush_object *self);

#ifdef PIO_UNIT_TESTING
void ssh_server_run_tests(void);
#endif

#endif // SSH_SERVER_H
