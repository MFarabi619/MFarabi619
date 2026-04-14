#include "coreutils.h"

#include <stdio.h>

int programs::coreutils::cmd_print(int argc, char **argv) {
  if (argc != 2) { printf("usage: print <text>\n"); return 1; }
  printf("%s", argv[1]);
  return 0;
}
