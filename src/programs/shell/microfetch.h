#ifndef SHELL_MICROFETCH_H
#define SHELL_MICROFETCH_H

#include <microshell.h>

namespace programs::shell::microfetch {

void registerNode(struct ush_object *ush);
const char *generate(void);

}

#endif
