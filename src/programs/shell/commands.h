#ifndef SHELL_COMMANDS_H
#define SHELL_COMMANDS_H

#include <microshell.h>

// Register global commands (actions, not data).
void commands_register(struct ush_object *ush);

#endif // SHELL_COMMANDS_H
