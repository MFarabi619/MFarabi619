#ifndef SHELL_H
#define SHELL_H

#include "../../config.h"
#include <microshell.h>

void shell_init(void);
void shell_service(void);
void shell_init_instance(struct ush_object *ush,
                         const struct ush_descriptor *desc);

char *shell_get_hostname(void);
void shell_set_hostname(const char *hostname);

#ifdef PIO_UNIT_TESTING
void shell_run_tests(void);
#endif

#endif // SHELL_H
