#include "coreutils.h"

#include <SD.h>
#include <stdio.h>
#include <string.h>

extern char g_cwd[];

static void resolve(const char *path, char *out, size_t cap) {
  if (path[0] == '/')
    strlcpy(out, path, cap);
  else
    snprintf(out, cap, "%s%s%s",
             g_cwd, (strcmp(g_cwd, "/") == 0) ? "" : "/", path);
}

int programs::coreutils::cmd_cp(int argc, char **argv) {
  if (argc < 3) { printf("usage: cp <src> <dst>\n"); return 1; }

  char src[128], dst[128];
  resolve(argv[1], src, sizeof(src));
  resolve(argv[2], dst, sizeof(dst));

  File in = SD.open(src, FILE_READ);
  if (!in) { printf("cp: cannot open %s\n", argv[1]); return 1; }

  File out = SD.open(dst, FILE_WRITE);
  if (!out) { in.close(); printf("cp: cannot create %s\n", argv[2]); return 1; }

  char buf[512];
  size_t total = 0;
  while (in.available()) {
    int n = in.readBytes(buf, sizeof(buf));
    if (n <= 0) break;
    out.write((uint8_t *)buf, n);
    total += n;
  }

  in.close();
  out.close();
  printf("copied %s -> %s (%u bytes)\n", argv[1], argv[2], (unsigned)total);
  return 0;
}
