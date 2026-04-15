#pragma once

#include <stddef.h>

namespace console::path {

void apply_cd(char *cwd, size_t cap, const char *arg);
const char *display_cwd(const char *cwd);
const char *home_dir();

}
