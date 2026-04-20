#pragma once
// Centralized Nerd Font glyph registry.
// Names match the Nerd Font cheat sheet: https://www.nerdfonts.com/cheat-sheet
// Format: NF_{source}_{name} in SCREAMING_SNAKE_CASE.
// Mirrors firmware/src/console/icons.rs

// ─── Font Awesome (nf-fa-*) ─────────────────────────────────────────────────

#define NF_FA_FILE           "\xef\x85\x9b"  // U+F15B
#define NF_FA_FILE_TEXT      "\xef\x85\x9c"  // U+F15C
#define NF_FA_FILE_IMAGE     "\xef\x87\x85"  // U+F1C5
#define NF_FA_FOLDER         "\xef\x81\xbb"  // U+F07B
#define NF_FA_FOLDER_OPEN    "\xef\x81\xbc"  // U+F07C

#define NF_FA_HOME           "\xef\x80\x95"  // U+F015
#define NF_FA_LOCK           "\xef\x80\xa3"  // U+F023
#define NF_FA_CLOCK          "\xef\x80\x97"  // U+F017
#define NF_FA_DATABASE       "\xef\x87\x80"  // U+F1C0
#define NF_FA_GLOBE          "\xef\x82\xac"  // U+F0AC
#define NF_FA_SERVER         "\xef\x88\xb3"  // U+F233
#define NF_FA_PLUG           "\xef\x87\xa6"  // U+F1E6
#define NF_FA_WIFI           "\xef\x87\xab"  // U+F1EB
#define NF_FA_COG            "\xef\x82\x85"  // U+F085
#define NF_FA_BOLT           "\xef\x83\xa7"  // U+F0E7
#define NF_FA_HDD            "\xef\x82\xa0"  // U+F0A0
#define NF_FA_LEAF           "\xef\x81\xac"  // U+F06C
#define NF_FA_THERMOMETER    "\xef\x8b\x89"  // U+F2C9
#define NF_FA_TINT           "\xef\x81\x83"  // U+F043
#define NF_FA_SITEMAP        "\xef\x87\xa0"  // U+F1E0
#define NF_FA_MICROCHIP      "\xef\x8b\x9b"  // U+F2DB
#define NF_FA_SIGNAL         "\xef\x8b\x88"  // U+F2C8
#define NF_FA_TERMINAL       "\xef\x84\xa0"  // U+F120
#define NF_FA_DESKTOP        "\xef\x84\x88"  // U+F108
#define NF_FA_MEMORY         "\xef\x94\xb8"  // U+F538

// ─── Dev Icons (nf-dev-*) ───────────────────────────────────────────────────

#define NF_DEV_RUST          "\xee\x9e\xa8"  // U+E7A8
#define NF_DEV_HTML5         "\xee\x9c\xb6"  // U+E736
#define NF_DEV_JAVASCRIPT    "\xee\x9d\x8e"  // U+E74E
#define NF_DEV_CSS3          "\xee\x9d\x89"  // U+E749

// ─── Seti UI (nf-seti-*) ───────────────────────────────────────────────────

#define NF_SETI_CONFIG       "\xee\x97\xbc"  // U+E5FC
#define NF_SETI_TOML         "\xee\x9a\xb2"  // U+E6B2
#define NF_SETI_JSON         "\xee\x98\x8b"  // U+E60B
#define NF_SETI_MARKDOWN     "\xee\x9c\xbe"  // U+E73E
#define NF_SETI_ORG          "\xee\x98\xb3"  // U+E633
#define NF_SETI_WASM         "\xee\x9a\xa1"  // U+E6A1

// ─── Custom / Linux (nf-linux-*) ────────────────────────────────────────────

#define NF_LINUX_NIX         "\xef\x8c\x93"  // U+F313

// ─── Material Design (nf-md-*) ──────────────────────────────────────────────

#define NF_MD_ARCH           "\xee\x89\xa6"  // U+E266
#define NF_MD_BINARY         "\xef\x91\xb1"  // U+F471
#define NF_MD_SSH            "\xef\x8b\x80"  // U+F2C0 (approx)
#define NF_MD_RAM            "\xef\x83\xa4"  // U+F0E4

// ─── Powerline (nf-ple-*) ───────────────────────────────────────────────────

#define NF_PLE_LEFT_HARD     "\xee\x82\xb0"  // U+E0B0
#define NF_PLE_RIGHT_HARD    "\xee\x82\xb2"  // U+E0B2
#define NF_PLE_LEFT_SOFT     "\xee\x82\xb1"  // U+E0B1
#define NF_PLE_RIGHT_SOFT    "\xee\x82\xb3"  // U+E0B3

// ─── Frame ──────────────────────────────────────────────────────────────────

#define FRAME_TOP_LEFT       "\xe2\x95\xad\xe2\x94\x80"  // ╭─
#define FRAME_BOT_LEFT       "\xe2\x95\xb0\xe2\x94\x80"  // ╰─
#define FRAME_LINE           "\xe2\x94\x80"               // ─

// ─── Misc Unicode ───────────────────────────────────────────────────────────

#define DEGREE_SIGN          "\xc2\xb0"  // °

