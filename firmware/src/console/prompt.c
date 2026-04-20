#include <console/ansi.h>
#include <console/icons.h>
#include <console/prompt.h>

#include <stdio.h>
#include <string.h>

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/net/hostname.h>
#include <zephyr/shell/shell.h>

LOG_MODULE_REGISTER(prompt);

#define PROMPT_BUFFER_SIZE 2048
#define PROMPT_FILL_TEXT "─"
#define PROMPT_END_TEXT "─╮"
#define PROMPT_SAFETY_COLUMNS 3

static const struct shell *global_shell;
static char prompt_buffer[PROMPT_BUFFER_SIZE];

struct prompt_segment {
  const char *text;
  int display_width;
};

uint16_t prompt_terminal_width(void) {
  if ((global_shell != NULL) && (global_shell->ctx != NULL) &&
      (global_shell->ctx->vt100_ctx.cons.terminal_wid > 0U)) {
    return global_shell->ctx->vt100_ctx.cons.terminal_wid;
  }

  return CONFIG_SHELL_DEFAULT_TERMINAL_WIDTH;
}

static const char *prompt_basename(const char *path) {
  const char *last_slash = strrchr(path, '/');

  if ((last_slash == NULL) || (*(last_slash + 1) == '\0')) {
    return path;
  }

  return last_slash + 1;
}

static const char *prompt_path_icon(const char *path) {
  if (strcmp(path, "/") == 0) {
    return NF_FA_LOCK;
  }

  if ((strcmp(path, "~") == 0) || (strncmp(path, "~/", 2) == 0)) {
    return NF_FA_HOME;
  }

  return NF_FA_FOLDER_OPEN;
}

/*
 * Keep this deliberately small and explicit.
 *
 * We only account for the handful of decorative glyphs we emit ourselves.
 * Plain text uses strlen().
 *
 * Adjust these values once for your terminal/font pair and keep the rest
 * simple.
 */
static int prompt_glyph_width(const char *glyph) {
  if (glyph == NULL) {
    return 0;
  }

  if ((strcmp(glyph, NF_FA_LOCK) == 0) || (strcmp(glyph, NF_FA_HOME) == 0) ||
      (strcmp(glyph, NF_FA_FOLDER_OPEN) == 0) ||
      (strcmp(glyph, NF_MD_RAM) == 0) || (strcmp(glyph, NF_MD_ARCH) == 0) ||
      (strcmp(glyph, NF_FA_CLOCK) == 0) ||
      (strcmp(glyph, NF_FA_MICROCHIP) == 0) ||
      (strcmp(glyph, NF_PLE_LEFT_HARD) == 0) ||
      (strcmp(glyph, NF_PLE_RIGHT_HARD) == 0) ||
      (strcmp(glyph, NF_PLE_RIGHT_SOFT) == 0)) {
    return 2;
  }

  if ((strcmp(glyph, PROMPT_FILL_TEXT) == 0) ||
      (strcmp(glyph, PROMPT_END_TEXT) == 0)) {
    return 1;
  }

  return 1;
}

static void append_text(char *buffer, size_t buffer_size, size_t *offset,
                        const char *text) {
  int written;

  if ((*offset >= buffer_size) || (text == NULL)) {
    return;
  }

  written = snprintf(buffer + *offset, buffer_size - *offset, "%s", text);
  if (written < 0) {
    return;
  }

  if ((size_t)written >= (buffer_size - *offset)) {
    *offset = buffer_size - 1U;
    return;
  }

  *offset += (size_t)written;
}

static int append_repeat_count_for_fill(int terminal_width, int left_width,
                                        int right_width) {
  int available_columns =
      terminal_width - left_width - right_width - PROMPT_SAFETY_COLUMNS;
  int fill_glyph_width = prompt_glyph_width(PROMPT_FILL_TEXT);

  if (available_columns <= 0) {
    return 0;
  }

  if (fill_glyph_width <= 0) {
    return 0;
  }

  return available_columns / fill_glyph_width;
}

static int prompt_left_width(const char *path_icon, const char *path_text) {
  int width = 0;

  /* " " chip " " + left hard + " " icon " " name " " + left hard */
  width += 1;
  width += prompt_glyph_width(NF_FA_MICROCHIP);
  width += 1;
  width += prompt_glyph_width(NF_PLE_LEFT_HARD);
  width += 1;
  width += prompt_glyph_width(path_icon);
  width += 1;
  width += (int)strlen(path_text);
  width += 1;
  width += prompt_glyph_width(NF_PLE_LEFT_HARD);

  return width;
}

static int prompt_right_width(const char *context_text,
                              const char *ram_percent_text,
                              const char *ram_free_text,
                              const char *uptime_text) {
  int width = 0;

  /* right hard + " " context " " */
  width += prompt_glyph_width(NF_PLE_RIGHT_HARD);
  width += 1;
  width += (int)strlen(context_text);
  width += 1;

  /* right hard + " " ram% " " ram icon " " ram_free " " */
  width += prompt_glyph_width(NF_PLE_RIGHT_HARD);
  width += 1;
  width += (int)strlen(ram_percent_text);
  width += 1;
  width += prompt_glyph_width(NF_MD_RAM);
  width += 1;
  width += (int)strlen(ram_free_text);
  width += 1;

  /* soft + " xtensa " arch */
  width += prompt_glyph_width(NF_PLE_RIGHT_SOFT);
  width += (int)strlen(" xtensa ");
  width += prompt_glyph_width(NF_MD_ARCH);
  width += 1;

  /* right hard + " " uptime " " clock " " */
  width += prompt_glyph_width(NF_PLE_RIGHT_HARD);
  width += 1;
  width += (int)strlen(uptime_text);
  width += 1;
  width += prompt_glyph_width(NF_FA_CLOCK);
  width += 1;

  /* end text */
  width += prompt_glyph_width(PROMPT_END_TEXT);

  return width;
}

static void prompt_format_uptime(char *buffer, size_t buffer_size) {
  uint32_t uptime_seconds = k_uptime_get() / 1000U;

  snprintf(buffer, buffer_size, "%lum%lus",
           (unsigned long)(uptime_seconds / 60U),
           (unsigned long)(uptime_seconds % 60U));
}

static void prompt_format_ram(char *free_buffer, size_t free_buffer_size,
                              char *percent_buffer,
                              size_t percent_buffer_size) {
#ifdef CONFIG_SYS_HEAP_RUNTIME_STATS
  extern struct k_heap _system_heap;
  struct sys_memory_stats stats;
  uint32_t total_bytes;
  uint32_t used_percent;

  sys_heap_runtime_stats_get(&_system_heap.heap, &stats);

  total_bytes = stats.free_bytes + stats.allocated_bytes;
  used_percent =
      (total_bytes > 0U) ? ((stats.allocated_bytes * 100U) / total_bytes) : 0U;

  if (stats.free_bytes >= (1024U * 1024U)) {
    snprintf(free_buffer, free_buffer_size, "%.1fM",
             stats.free_bytes / (1024.0f * 1024.0f));
  } else {
    snprintf(free_buffer, free_buffer_size, "%.1fK",
             stats.free_bytes / 1024.0f);
  }

  snprintf(percent_buffer, percent_buffer_size, "%lu%%",
           (unsigned long)used_percent);
#else
  snprintf(free_buffer, free_buffer_size, "?");
  snprintf(percent_buffer, percent_buffer_size, "?");
#endif
}

static const char *build_prompt(const char *current_path) {
  const char *hostname;
  const char *path_icon;
  const char *path_text;

  char context_text[80];
  char uptime_text[24];
  char ram_free_text[16];
  char ram_percent_text[8];

  int terminal_width;
  int left_width;
  int right_width;
  int fill_count;

  size_t offset = 0U;

  hostname = net_hostname_get();
  path_icon = prompt_path_icon(current_path);
  path_text = prompt_basename(current_path);

  snprintf(context_text, sizeof(context_text), "root@%s",
           (hostname != NULL) ? hostname : "zephyr");

  prompt_format_uptime(uptime_text, sizeof(uptime_text));
  prompt_format_ram(ram_free_text, sizeof(ram_free_text), ram_percent_text,
                    sizeof(ram_percent_text));

  terminal_width = (int)prompt_terminal_width();
  left_width = prompt_left_width(path_icon, path_text);
  right_width = prompt_right_width(context_text, ram_percent_text,
                                   ram_free_text, uptime_text);
  fill_count =
      append_repeat_count_for_fill(terminal_width, left_width, right_width);

  prompt_buffer[0] = '\0';

  /* Left side */
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset,
              ANSI_DIM FRAME_TOP_LEFT ANSI_RESET);
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset,
              PROMPT_OS_BG PROMPT_OS_FG " " NF_FA_MICROCHIP " ");
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset,
              PROMPT_DIR_BG PROMPT_OS_BG_AS_FG NF_PLE_LEFT_HARD);
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset,
              PROMPT_DIR_BG PROMPT_DIR_FG " ");
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset, path_icon);
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset, " ");
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset, path_text);
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset, " ");
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset,
              ANSI_RESET PROMPT_DIR_BG_AS_FG NF_PLE_LEFT_HARD ANSI_RESET);

  /* Fill */
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset, ANSI_DIM);
  for (int index = 0; index < fill_count; ++index) {
    append_text(prompt_buffer, sizeof(prompt_buffer), &offset,
                PROMPT_FILL_TEXT);
  }
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset, ANSI_RESET);

  /* Right side */
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset,
              PROMPT_CTX_BG_AS_FG NF_PLE_RIGHT_HARD);
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset,
              PROMPT_CTX_BG PROMPT_CTX_FG " ");
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset, context_text);
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset, " ");

  append_text(prompt_buffer, sizeof(prompt_buffer), &offset,
              PROMPT_RAM_BG PROMPT_RAM_FG NF_PLE_RIGHT_HARD " ");
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset, ram_percent_text);
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset, " ");
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset, NF_MD_RAM);
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset, " ");
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset, ram_free_text);
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset, " ");

  append_text(prompt_buffer, sizeof(prompt_buffer), &offset,
              NF_PLE_RIGHT_SOFT " xtensa ");
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset, NF_MD_ARCH);
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset, " ");

  append_text(prompt_buffer, sizeof(prompt_buffer), &offset,
              PROMPT_ARCH_BG PROMPT_CLOCK_BG_AS_FG NF_PLE_RIGHT_HARD);
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset,
              PROMPT_CLOCK_BG PROMPT_CLOCK_FG " ");
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset, uptime_text);
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset, " ");
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset, NF_FA_CLOCK);
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset, " ");
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset,
              ANSI_RESET ANSI_DIM PROMPT_END_TEXT ANSI_RESET);

  /* New input line */
  append_text(prompt_buffer, sizeof(prompt_buffer), &offset,
              "\r\n" ANSI_DIM FRAME_BOT_LEFT ANSI_RESET " ");

  return prompt_buffer;
}

bool prompt_init(const struct shell *shell) {
  global_shell = shell;
  prompt_update(shell);
  return true;
}

void prompt_update(const struct shell *shell) {
  const char *prompt = build_prompt("/");
  shell_prompt_change(shell, prompt);
}

void prompt_print_motd(const struct shell *shell, const char *remote_ip) {
  const char *hostname = net_hostname_get();

  ARG_UNUSED(remote_ip);

  shell_fprintf(shell, SHELL_NORMAL,
                "\r\n"
                "Welcome to %s!\r\n"
                "\r\n"
                "System information:     microfetch\r\n"
                "Hardware sensors:       sensor get\r\n"
                "Network interfaces:     net iface\r\n"
                "Memory usage:           kernel stacks\r\n"
                "Show all commands:      help\r\n"
                "\r\n",
                (hostname != NULL) ? hostname : "zephyr");
}

//---

#if defined(CONFIG_ZTEST) && defined(CONFIG_TEST_PROMPT)
#include <zephyr/ztest.h>

ZTEST_SUITE(prompt, NULL, NULL, NULL, NULL, NULL);

ZTEST(prompt, test_visible_width_plain) {
  zassert_equal(visible_width("hello"), 5);
}

ZTEST(prompt, test_visible_width_ansi) {
  zassert_equal(visible_width("\x1b[31mred\x1b[0m"), 3);
}

ZTEST(prompt, test_visible_width_utf8_2byte) {
  zassert_equal(visible_width("\xc2\xb0"), 1);
}

ZTEST(prompt, test_cwd_glyph_root) {
  zassert_str_equal(cwd_glyph("/"), NF_FA_LOCK);
}

ZTEST(prompt, test_cwd_glyph_home) {
  zassert_str_equal(cwd_glyph("~"), NF_FA_HOME);
}

ZTEST(prompt, test_cwd_glyph_dir) {
  zassert_str_equal(cwd_glyph("/var/log"), NF_FA_FOLDER_OPEN);
}

ZTEST(prompt, test_last_path_component_nested) {
  zassert_str_equal(last_path_component("/var/log"), "log");
}

ZTEST(prompt, test_last_path_component_root) {
  zassert_str_equal(last_path_component("/"), "/");
}
#endif
