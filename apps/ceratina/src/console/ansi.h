#pragma once
// ANSI escape codes for terminal output.
// Mirrors firmware/src/programs/shell.rs prompt color scheme.

// ─── Attributes ─────────────────────────────────────────────────────────────

#define ANSI_RESET         "\x1b[0m"
#define ANSI_BOLD          "\x1b[1m"
#define ANSI_DIM           "\x1b[2m"

#define ANSI_CLEAR_SCREEN  "\x1b[2J\x1b[H"
#define ANSI_CLEAR_LINE    "\x1b[K"

// ─── Foreground ─────────────────────────────────────────────────────────────

#define ANSI_FG_BLACK      "\x1b[30m"
#define ANSI_FG_RED        "\x1b[31m"
#define ANSI_FG_GREEN      "\x1b[32m"
#define ANSI_FG_YELLOW     "\x1b[33m"
#define ANSI_FG_BLUE       "\x1b[34m"
#define ANSI_FG_MAGENTA    "\x1b[35m"
#define ANSI_FG_CYAN       "\x1b[36m"
#define ANSI_FG_WHITE      "\x1b[37m"

// ─── Background ─────────────────────────────────────────────────────────────

#define ANSI_BG_BLACK      "\x1b[40m"
#define ANSI_BG_RED        "\x1b[41m"
#define ANSI_BG_GREEN      "\x1b[42m"
#define ANSI_BG_YELLOW     "\x1b[43m"
#define ANSI_BG_BLUE       "\x1b[44m"
#define ANSI_BG_MAGENTA    "\x1b[45m"
#define ANSI_BG_CYAN       "\x1b[46m"
#define ANSI_BG_WHITE      "\x1b[47m"

// ─── Prompt Segments (Powerlevel10k style) ──────────────────────────────────

#define PROMPT_OS_FG       ANSI_FG_BLACK
#define PROMPT_OS_BG       ANSI_BG_BLUE
#define PROMPT_OS_BG_AS_FG ANSI_FG_BLUE

#define PROMPT_DIR_FG      ANSI_FG_BLACK
#define PROMPT_DIR_BG      ANSI_BG_MAGENTA
#define PROMPT_DIR_BG_AS_FG ANSI_FG_MAGENTA

#define PROMPT_ARCH_FG     ANSI_FG_BLACK
#define PROMPT_ARCH_BG     ANSI_BG_YELLOW
#define PROMPT_ARCH_BG_AS_FG ANSI_FG_YELLOW

#define PROMPT_CTX_FG      ANSI_FG_YELLOW
#define PROMPT_CTX_BG      ANSI_BG_BLACK
#define PROMPT_CTX_BG_AS_FG ANSI_FG_BLACK

#define PROMPT_RAM_FG      ANSI_FG_BLACK
#define PROMPT_RAM_BG      ANSI_BG_YELLOW
#define PROMPT_RAM_BG_AS_FG ANSI_FG_YELLOW

#define PROMPT_CLOCK_FG    ANSI_FG_BLACK
#define PROMPT_CLOCK_BG    ANSI_BG_WHITE
#define PROMPT_CLOCK_BG_AS_FG ANSI_FG_WHITE

#define PROMPT_FRAME       ANSI_DIM
#define PROMPT_ERROR       ANSI_FG_RED
#define PROMPT_WARN        ANSI_FG_YELLOW

