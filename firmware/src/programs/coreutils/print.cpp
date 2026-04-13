#include "print.h"

namespace {

void exec(struct ush_object *self,
          struct ush_file_descriptor const *file,
          int argc, char *argv[]) {
  (void)file;
  if (argc != 2) {
    ush_print_status(self, USH_STATUS_ERROR_COMMAND_WRONG_ARGUMENTS);
    return;
  }
  ush_print(self, argv[1]);
}

}

const struct ush_file_descriptor programs::coreutils::print::descriptor = {
  .name = "print",
  .description = "print argument to shell",
  .help = "usage: print <text>\r\n",
  .exec = exec,
};
