#include "coreutils.h"

#include <SD.h>
#include <stdio.h>
#include <string.h>

extern char g_cwd[];

int programs::coreutils::cmd_touch(int argc, char **argv) {
  if (argc < 2) { printf("usage: touch <file>\n"); return 1; }

  char resolved[128];
  if (argv[1][0] == '/')
    strlcpy(resolved, argv[1], sizeof(resolved));
  else
    snprintf(resolved, sizeof(resolved), "%s%s%s",
             g_cwd, (strcmp(g_cwd, "/") == 0) ? "" : "/", argv[1]);

  File f = SD.open(resolved, FILE_WRITE);
  if (!f) {
    printf("touch: failed to create %s\n", argv[1]);
    return 1;
  }
  f.close();
  printf("created %s\n", argv[1]);
  return 0;
}
