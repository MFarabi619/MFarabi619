#ifndef SHELL_COMMANDS_H
#define SHELL_COMMANDS_H

#include <microshell.h>

namespace programs::shell::commands {

void registerAll(struct ush_object *ush);

}

#endif // SHELL_COMMANDS_H
