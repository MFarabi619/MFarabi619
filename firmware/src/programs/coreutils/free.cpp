#include "coreutils.h"
#include <services/system.h>

#include <stdio.h>

int programs::coreutils::cmd_free(int argc, char **argv) {
  (void)argv;
  if (argc != 1) { printf("usage: free\n"); return 1; }

  SystemQuery query = {
    .preferred_storage = StorageKind::LittleFS,
    .snapshot = {},
  };
  services::system::accessSnapshot(&query);
  printf("heap total: %u\nheap free:  %u\nheap used:  %u\n",
         query.snapshot.heap_total, query.snapshot.heap_free,
         query.snapshot.heap_total - query.snapshot.heap_free);
  return 0;
}
