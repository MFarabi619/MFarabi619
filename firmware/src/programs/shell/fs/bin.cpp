#include "../../coreutils/coreutils.h"

#include <microshell.h>
static struct ush_node_object bin;

void bin_mount(struct ush_object *ush) {
  size_t count = 0;
  const struct ush_file_descriptor *files = programs::coreutils::descriptors(&count);
  ush_node_mount(ush, "/bin", &bin, files, count);
}
