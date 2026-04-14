#include "coreutils.h"

#include "../../services/identity.h"

namespace {

void exec(struct ush_object *self,
          struct ush_file_descriptor const *file,
          int argc, char *argv[]) {
  (void)file;
  if (argc == 1) {
    ush_printf(self, "%s\r\n", services::identity::accessHostname());
    return;
  }

  if (argc == 2) {
    if (services::identity::configureHostname(argv[1])) {
      ush_print(self, (char *)"hostname updated\r\n");
    } else {
      ush_print(self, (char *)"failed to update hostname\r\n");
    }
    return;
  }

  ush_print_status(self, USH_STATUS_ERROR_COMMAND_WRONG_ARGUMENTS);
}

}

const struct ush_file_descriptor programs::coreutils::hostname::descriptor = {
  .name = "hostname",
  .description = "read or set hostname",
  .help = "usage: hostname [new-name]\r\n",
  .exec = exec,
};
