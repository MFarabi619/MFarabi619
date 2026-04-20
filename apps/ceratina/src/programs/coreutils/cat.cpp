#include "coreutils.h"
#include "console/path.h"

#include <SD.h>
#include <stdio.h>
#include <string.h>

extern char g_cwd[];

int programs::coreutils::cmd_cat(int argc, char **argv) {
  if (argc < 2) { printf("usage: cat <file>\n"); return 1; }

  const char *path = argv[1];
  char resolved[128];

  if (path[0] == '/') {
    strlcpy(resolved, path, sizeof(resolved));
  } else {
    snprintf(resolved, sizeof(resolved), "%s%s%s",
             g_cwd, (strcmp(g_cwd, "/") == 0) ? "" : "/", path);
  }

  File f = SD.open(resolved, FILE_READ);
  if (!f) { printf("cat: %s: no such file\n", path); return 1; }
  if (f.isDirectory()) { f.close(); printf("cat: %s: is a directory\n", path); return 1; }

  char buf[512];
  while (f.available()) {
    int n = f.readBytes(buf, sizeof(buf) - 1);
    if (n <= 0) break;
    buf[n] = '\0';
    printf("%s", buf);
  }
  f.close();
  printf("\n");
  return 0;
}
