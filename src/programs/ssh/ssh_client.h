#ifndef SSH_CLIENT_H
#define SSH_CLIENT_H

#include <microshell.h>

// Register SSH client shell commands (ssh-exec, scp-get, scp-put, ota).
void ssh_client_commands_register(struct ush_object *ush);

#endif // SSH_CLIENT_H
