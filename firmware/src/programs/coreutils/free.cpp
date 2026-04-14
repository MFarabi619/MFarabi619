#include "coreutils.h"

#include "../../services/system.h"

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

  char buf[128];
  SystemQuery query = {
    .preferred_storage = StorageKind::LittleFS,
    .snapshot = {},
  };
  services::system::accessSnapshot(&query);
  snprintf(buf, sizeof(buf),
           "heap total: %u\r\nheap free:  %u\r\nheap used:  %u\r\n",
           query.snapshot.heap_total, query.snapshot.heap_free,
           query.snapshot.heap_total - query.snapshot.heap_free);
  ush_print(self, buf);
}

}

const struct ush_file_descriptor programs::coreutils::free::descriptor = {
  .name = "free",
  .description = "show memory usage",
  .help = "usage: free\r\n",
  .exec = exec,
};
