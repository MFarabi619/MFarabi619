#ifndef CONSOLE_PROMPT_H
#define CONSOLE_PROMPT_H

#include <stdint.h>
#include <stdbool.h>
#include <zephyr/shell/shell.h>

bool prompt_init(const struct shell *sh);
void prompt_update(const struct shell *sh);
void prompt_print_motd(const struct shell *sh, const char *remote_ip);

uint16_t prompt_terminal_width(void);
void prompt_set_terminal_width(uint16_t w);

int visible_width(const char *s);
const char *last_path_component(const char *path);
const char *cwd_glyph(const char *cwd);

#endif /* CONSOLE_PROMPT_H */
