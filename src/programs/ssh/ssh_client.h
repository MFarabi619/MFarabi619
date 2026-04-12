#ifndef SSH_CLIENT_H
#define SSH_CLIENT_H

#include <microshell.h>

namespace programs::ssh_client {

void registerCommands(struct ush_object *ush);

}

#endif // SSH_CLIENT_H
