#pragma once

#include <stdint.h>

namespace console::prompt {

const char *build(const char *cwd);
const char *build_motd(const char *remote_ip = nullptr);

void detect_width();
void set_terminal_width(uint16_t w);
uint16_t terminal_width();

}
