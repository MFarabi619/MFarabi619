#include "path.h"

#include <string.h>
#include <stdio.h>

//------------------------------------------
//  Path utilities — port of Rust path.rs
//------------------------------------------

const char *console::path::home_dir() {
  return "/";
}

const char *console::path::display_cwd(const char *cwd) {
  static char display[128];
  const char *home = home_dir();
  size_t home_len = strlen(home);

  if (strcmp(cwd, home) == 0) {
    return "~";
  }

  if (home_len > 1 && strncmp(cwd, home, home_len) == 0) {
    snprintf(display, sizeof(display), "~%s", cwd + home_len);
    return display;
  }

  return cwd;
}

void console::path::apply_cd(char *cwd, size_t cap, const char *arg) {
  if (!arg || arg[0] == '\0' || strcmp(arg, "~") == 0) {
    strlcpy(cwd, home_dir(), cap);
    return;
  }

  if (strcmp(arg, "/") == 0) {
    strlcpy(cwd, "/", cap);
    return;
  }

  // Absolute path — start fresh
  char work[128];
  if (arg[0] == '/') {
    strlcpy(work, "/", sizeof(work));
    arg++;
  } else if (arg[0] == '~' && (arg[1] == '/' || arg[1] == '\0')) {
    strlcpy(work, home_dir(), sizeof(work));
    arg += (arg[1] == '/') ? 2 : 1;
  } else {
    strlcpy(work, cwd, sizeof(work));
  }

  // Walk each path component
  char component[64];
  while (*arg) {
    const char *slash = strchr(arg, '/');
    size_t len = slash ? (size_t)(slash - arg) : strlen(arg);

    if (len == 0 || (len == 1 && arg[0] == '.')) {
      // empty or "." — skip
    } else if (len == 2 && arg[0] == '.' && arg[1] == '.') {
      // ".." — go up
      char *last_slash = strrchr(work, '/');
      if (last_slash && last_slash != work) {
        *last_slash = '\0';
      } else {
        strlcpy(work, "/", sizeof(work));
      }
    } else {
      // regular name — append
      if (len >= sizeof(component)) len = sizeof(component) - 1;
      memcpy(component, arg, len);
      component[len] = '\0';

      if (strcmp(work, "/") != 0)
        strlcat(work, "/", sizeof(work));
      strlcat(work, component, sizeof(work));
    }

    if (!slash) break;
    arg = slash + 1;
  }

  strlcpy(cwd, work, cap);
}
