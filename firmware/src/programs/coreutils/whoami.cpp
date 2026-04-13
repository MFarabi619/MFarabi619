#include "whoami.h"

#include "../../config.h"

namespace {

void exec(struct ush_object *self,
          struct ush_file_descriptor const *file,
          int argc, char *argv[]) {
  (void)file;
  (void)argv;
  if (argc != 1) {
    ush_print_status(self, USH_STATUS_ERROR_COMMAND_WRONG_ARGUMENTS);
    return;
  }
  ush_printf(self, "%s\r\n", CONFIG_SSH_USER);
}

}

const struct ush_file_descriptor programs::coreutils::whoami::descriptor = {
  .name = "whoami",
  .description = "print current user",
  .help = "usage: whoami\r\n",
  .exec = exec,
};
