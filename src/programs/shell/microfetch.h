#ifndef SHELL_MICROFETCH_H
#define SHELL_MICROFETCH_H

#include <microshell.h>

void microfetch_register(struct ush_object *ush);
const char *microfetch_generate(void);

#endif
