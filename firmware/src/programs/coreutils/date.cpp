#include "coreutils.h"
#include "networking/sntp.h"
#include "services/rtc.h"

#include <stdio.h>

int programs::coreutils::cmd_date(int argc, char **argv) {
  (void)argv;
  if (argc != 1) { printf("usage: date\n"); return 1; }

  if (networking::sntp::isSynced()) {
    printf("%s\n", networking::sntp::accessLocalTimeString());
    return 0;
  }

  RTCSnapshot snapshot = {};
  if (services::rtc::accessSnapshot(&snapshot) && snapshot.valid) {
    printf("%s\n", snapshot.iso8601);
    return 0;
  }

  printf("(no time)\n");
  return 0;
}
