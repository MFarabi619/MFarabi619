#ifndef PROGRAMS_COREUTILS_COREUTILS_H
#define PROGRAMS_COREUTILS_COREUTILS_H

#include <microshell.h>
#include <stddef.h>

namespace programs::coreutils {

const struct ush_file_descriptor *descriptors(size_t *count);

namespace date { extern const struct ush_file_descriptor descriptor; }
namespace free { extern const struct ush_file_descriptor descriptor; }
namespace hostname { extern const struct ush_file_descriptor descriptor; }
namespace ifconfig { extern const struct ush_file_descriptor descriptor; }
namespace print { extern const struct ush_file_descriptor descriptor; }
namespace sensors { extern const struct ush_file_descriptor descriptor; }
namespace uptime { extern const struct ush_file_descriptor descriptor; }
namespace whoami { extern const struct ush_file_descriptor descriptor; }

}

#endif
