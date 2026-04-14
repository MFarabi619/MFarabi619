#include "coreutils.h"
#include "../../services/system.h"

#include <stdio.h>
#include <string.h>

int programs::coreutils::cmd_uptime(int argc, char **argv) {
  (void)argv;
  if (argc != 1) { printf("usage: uptime\n"); return 1; }

  char buf[32];
  SystemQuery query = {
    .preferred_storage = StorageKind::LittleFS,
    .snapshot = {},
  };
  services::system::accessSnapshot(&query);
  services::system::formatUptime(buf, sizeof(buf), query.snapshot.uptime_seconds);
  printf("%s\n", buf);
  return 0;
}
