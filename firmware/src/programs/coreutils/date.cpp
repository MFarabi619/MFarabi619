#include "date.h"

#include "../../networking/sntp.h"
#include "../../services/rtc.h"

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

  if (networking::sntp::isSynced()) {
    ush_printf(self, "%s\r\n", networking::sntp::accessLocalTimeString());
    return;
  }

  RTCSnapshot snapshot = {};
  if (services::rtc::accessSnapshot(&snapshot) && snapshot.valid) {
    ush_printf(self, "%s\r\n", snapshot.iso8601);
    return;
  }

  ush_print(self, (char *)"(no time)\r\n");
}

}

const struct ush_file_descriptor programs::coreutils::date::descriptor = {
  .name = "date",
  .description = "show local date and time",
  .help = "usage: date\r\n",
  .exec = exec,
};
