#include "uptime.h"

#include "../../services/system.h"

#include <string.h>

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

  char buf[32];
  SystemQuery query = {
    .preferred_storage = StorageKind::LittleFS,
    .snapshot = {},
  };
  services::system::accessSnapshot(&query);
  services::system::formatUptime(buf, sizeof(buf), query.snapshot.uptime_seconds);
  strncat(buf, "\r\n", sizeof(buf) - strlen(buf) - 1);
  ush_print(self, buf);
}

}

const struct ush_file_descriptor programs::coreutils::uptime::descriptor = {
  .name = "uptime",
  .description = "show system uptime",
  .help = "usage: uptime\r\n",
  .exec = exec,
};
