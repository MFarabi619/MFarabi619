#ifndef SHELL_H
#define SHELL_H

#include "../../config.h"
#include <microshell.h>

namespace programs::shell {

void initialize();
void service();
void initInstance(struct ush_object *ush,
                  const struct ush_descriptor *desc);

#ifdef PIO_UNIT_TESTING
void test();
#endif

}

#endif
