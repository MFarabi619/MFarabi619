#include "coreutils.h"
#include <config.h>

#include <stdio.h>

int programs::coreutils::cmd_whoami(int argc, char **argv) {
  (void)argv;
  if (argc != 1) { printf("usage: whoami\n"); return 1; }
  printf("%s\n", CONFIG_SSH_USER);
  return 0;
}
