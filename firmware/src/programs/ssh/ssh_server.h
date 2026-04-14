#ifndef SSH_SERVER_H
#define SSH_SERVER_H

#include "../../config.h"

struct ush_object;

namespace services::sshd {

bool initialize();
bool requestExit(struct ush_object *self);

#ifdef PIO_UNIT_TESTING
void test();
#endif

}

#endif // SSH_SERVER_H
