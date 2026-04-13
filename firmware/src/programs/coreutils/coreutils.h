#ifndef PROGRAMS_COREUTILS_COREUTILS_H
#define PROGRAMS_COREUTILS_COREUTILS_H

#include <microshell.h>
#include <stddef.h>

namespace programs::coreutils {

const struct ush_file_descriptor *descriptors(size_t *count);

}

#endif
