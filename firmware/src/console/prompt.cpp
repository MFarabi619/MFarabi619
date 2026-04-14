#include "prompt.h"
#include "ansi.h"
#include "icons.h"
#include <identity.h>
#include "../networking/sntp.h"
#include <config.h>

#include <Arduino.h>
#include <stdio.h>
#include <string.h>

namespace {

uint16_t g_terminal_width = 0;

// Probe terminal width using VT100 escape sequences:
// 1. Save cursor position
// 2. Move cursor to column 999 (far right — terminal clamps to last column)
// 3. Query cursor position (DSR → CPR response: \x1b[row;colR)
// 4. Restore cursor position
// Returns 0 on failure (no response / timeout).
uint16_t probe_terminal_width() {
  while (Serial.available()) Serial.read();

  Serial.print("\x1b[s\x1b[999C\x1b[6n\x1b[u");
  Serial.flush();

  char buf[16];
  size_t pos = 0;
  int timeout_ms = 500;
  const int poll_ms = 5;

  while (timeout_ms > 0 && pos < sizeof(buf) - 1) {
    if (Serial.available()) {
      char c = Serial.read();
      buf[pos++] = c;
      if (c == 'R') break;
    } else {
      delay(poll_ms);
      timeout_ms -= poll_ms;
    }
  }
  buf[pos] = '\0';

  // Parse \x1b[row;colR
  char *semi = strchr(buf, ';');
  if (!semi) return 0;
  uint16_t col = (uint16_t)atoi(semi + 1);
  return col > 0 ? col : 0;
}

// Prompt buffer — large enough for two-line powerline with ANSI escapes.
// ANSI sequences are invisible but consume bytes. Each segment has ~20 bytes
// of escape codes. With 8 segments + frame + fill, 1024 is comfortable.
char g_prompt[2048];

const char *cwd_glyph(const char *cwd) {
  if (strcmp(cwd, "/") == 0) return NF_FA_LOCK;
  if (strcmp(cwd, "~") == 0 || strncmp(cwd, "~/", 2) == 0) return NF_FA_HOME;
  return NF_FA_FOLDER_OPEN;
}

int visible_width(const char *s) {
  int w = 0;
  bool in_esc = false;
  while (*s) {
    if (*s == '\x1b') {
      in_esc = true;
      s++;
      continue;
    }
    if (in_esc) {
      if ((*s >= 'A' && *s <= 'Z') || (*s >= 'a' && *s <= 'z'))
        in_esc = false;
      s++;
      continue;
    }
    unsigned char c = (unsigned char)*s;
    if (c < 0x80) {
      w++;
      s++;
    } else if ((c & 0xE0) == 0xC0) {
      w++; s += 2;
    } else if ((c & 0xF0) == 0xE0) {
      w++; s += 3;
    } else if ((c & 0xF8) == 0xF0) {
      w++; s += 4;
    } else {
      s++;
    }
  }
  return w;
}

const char *last_path_component(const char *cwd) {
  const char *p = strrchr(cwd, '/');
  if (!p || *(p + 1) == '\0') return cwd;
  return p + 1;
}

} // namespace

void console::prompt::detect_width() {
  uint16_t w = probe_terminal_width();
  if (w > 0) {
    g_terminal_width = w;
    Serial.printf("[console] terminal width: %u\n", w);
  } else {
    g_terminal_width = 80;
    Serial.println("[console] width probe failed, defaulting to 80");
  }
}

void console::prompt::set_terminal_width(uint16_t w) {
  g_terminal_width = w;
}

uint16_t console::prompt::terminal_width() {
  if (g_terminal_width == 0) g_terminal_width = 80;
  return g_terminal_width;
}

const char *console::prompt::build(const char *cwd) {
  const char *display = last_path_component(cwd);
  const char *glyph = cwd_glyph(cwd);
  const char *hostname = services::identity::accessHostname();

  // Time string
  char time_str[24];
  if (networking::sntp::isSynced()) {
    uint32_t epoch = networking::sntp::accessUTCEpoch();
    uint32_t secs_of_day = epoch % 86400;
    uint32_t hour24 = secs_of_day / 3600;
    uint32_t minute = (secs_of_day % 3600) / 60;
    uint32_t second = secs_of_day % 60;
    uint32_t hour12;
    const char *ampm;
    if (hour24 == 0)       { hour12 = 12; ampm = "AM"; }
    else if (hour24 < 12)  { hour12 = hour24; ampm = "AM"; }
    else if (hour24 == 12) { hour12 = 12; ampm = "PM"; }
    else                   { hour12 = hour24 - 12; ampm = "PM"; }
    snprintf(time_str, sizeof(time_str), "%02lu:%02lu:%02lu %s",
             (unsigned long)hour12, (unsigned long)minute,
             (unsigned long)second, ampm);
  } else {
    unsigned long uptime = millis() / 1000;
    snprintf(time_str, sizeof(time_str), "%lum%lus", uptime / 60, uptime % 60);
  }

  // RAM
  uint32_t heap_free = ESP.getFreeHeap();
  uint32_t heap_total = ESP.getHeapSize();
  uint32_t heap_pct = heap_total > 0 ? ((heap_total - heap_free) * 100) / heap_total : 0;
  char ram_str[16];
  if (heap_free >= 1024 * 1024)
    snprintf(ram_str, sizeof(ram_str), "%.1fM", heap_free / (1024.0f * 1024.0f));
  else
    snprintf(ram_str, sizeof(ram_str), "%.1fK", heap_free / 1024.0f);
  char ram_pct[8];
  snprintf(ram_pct, sizeof(ram_pct), "%lu%%", (unsigned long)heap_pct);

  // Context
  char context[80];
  snprintf(context, sizeof(context), "%s@%s", CONFIG_SSH_USER, hostname);

  // Build left segment
  char left[256];
  snprintf(left, sizeof(left),
    ANSI_DIM FRAME_TOP_LEFT ANSI_RESET
    PROMPT_OS_BG PROMPT_OS_FG " " NF_FA_MICROCHIP " "
    PROMPT_DIR_BG PROMPT_OS_BG_AS_FG NF_PLE_LEFT_HARD
    PROMPT_DIR_BG PROMPT_DIR_FG " %s %s "
    ANSI_RESET PROMPT_DIR_BG_AS_FG NF_PLE_LEFT_HARD ANSI_RESET,
    glyph, display);

  // Build right segment
  char right[384];
  snprintf(right, sizeof(right),
    PROMPT_CTX_BG_AS_FG NF_PLE_RIGHT_HARD
    PROMPT_CTX_BG PROMPT_CTX_FG " %s "
    PROMPT_RAM_BG PROMPT_RAM_FG NF_PLE_RIGHT_HARD " "
    PROMPT_RAM_BG PROMPT_RAM_FG "%s " NF_MD_RAM " %s "
    NF_PLE_RIGHT_SOFT " xtensa " NF_MD_ARCH " "
    PROMPT_ARCH_BG PROMPT_CLOCK_BG_AS_FG NF_PLE_RIGHT_HARD
    PROMPT_CLOCK_BG PROMPT_CLOCK_FG " %s " NF_FA_CLOCK " " ANSI_RESET
    ANSI_DIM "\xe2\x94\x80\xe2\x95\xae" ANSI_RESET,
    context, ram_pct, ram_str, time_str);

  int left_vis = visible_width(left);
  int right_vis = visible_width(right);

  int fill = (int)g_terminal_width - left_vis - right_vis;
  if (fill < 1) fill = 1;

  // Assemble directly into g_prompt — no intermediate fill buffer
  int pos = snprintf(g_prompt, sizeof(g_prompt), "%s" ANSI_DIM, left);
  for (int i = 0; i < fill && pos < (int)sizeof(g_prompt) - 4; i++) {
    g_prompt[pos++] = '\xe2';
    g_prompt[pos++] = '\x94';
    g_prompt[pos++] = '\x80';
  }
  pos += snprintf(g_prompt + pos, sizeof(g_prompt) - pos,
    ANSI_RESET "%s\r\n" ANSI_DIM FRAME_BOT_LEFT ANSI_RESET " ", right);

  return g_prompt;
}

const char *console::prompt::build_motd() {
  static char motd[512];
  const char *hostname = services::identity::accessHostname();

  snprintf(motd, sizeof(motd),
    "\r\n"
    "Welcome to %s!\r\n"
    "\r\n"
    "System information:     microfetch\r\n"
    "Hardware sensors:       sensors\r\n"
    "Network interfaces:     ifconfig\r\n"
    "Memory usage:           free\r\n"
    "Show all commands:      help\r\n"
    "\r\n",
    hostname);

  return motd;
}
