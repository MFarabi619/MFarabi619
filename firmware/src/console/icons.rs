#![rustfmt::skip]


// Centralized Nerd Font glyph registry.
//
// Names match the Nerd Font cheat sheet: https://www.nerdfonts.com/cheat-sheet
// Format: NF_{source}_{name} in SCREAMING_SNAKE_CASE.

// ─── Font Awesome (nf-fa-*) ─────────────────────────────────────────────────

pub const NF_FA_FILE:         &str = "\u{f15b}";
pub const NF_FA_FILE_TEXT:    &str = "\u{f15c}";
pub const NF_FA_FILE_IMAGE:   &str = "\u{f1c5}";
pub const NF_FA_FOLDER:       &str = "\u{f07b}";
pub const NF_FA_FOLDER_OPEN:  &str = "\u{f07c}";

pub const NF_FA_HOME:         &str = "\u{f015}";
pub const NF_FA_LOCK:         &str = "\u{f023}";
pub const NF_FA_CLOCK:        &str = "\u{f017}";
pub const NF_FA_DATABASE:     &str = "\u{f1c0}";
pub const NF_FA_GLOBE:        &str = "\u{f0ac}";
pub const NF_FA_SERVER:       &str = "\u{f233}";
pub const NF_FA_PLUG:         &str = "\u{f1e6}";
pub const NF_FA_WIFI:         &str = "\u{f1eb}";
pub const NF_FA_COG:          &str = "\u{f085}";
pub const NF_FA_BOLT:         &str = "\u{f0e7}";
pub const NF_FA_HDD:          &str = "\u{f0a0}";
pub const NF_FA_LEAF:         &str = "\u{f06c}";
pub const NF_FA_THERMOMETER:  &str = "\u{f2c9}";
pub const NF_FA_TINT:         &str = "\u{f043}";
pub const NF_FA_SITEMAP:      &str = "\u{f1e0}";
pub const NF_FA_MICROCHIP:    &str = "\u{f2db}";
pub const NF_FA_SIGNAL:       &str = "\u{f2c8}";
pub const NF_FA_DOWNLOAD:     &str = "\u{f498}";
pub const NF_FA_TERMINAL:     &str = "\u{f120}";
pub const NF_FA_DESKTOP:      &str = "\u{f108}";
pub const NF_FA_MEMORY:       &str = "\u{f538}";

// ─── Dev Icons (nf-dev-*) ───────────────────────────────────────────────────

pub const NF_DEV_RUST:        &str = "\u{e7a8}";
pub const NF_DEV_HTML5:       &str = "\u{e736}";
pub const NF_DEV_JAVASCRIPT:  &str = "\u{e74e}";
pub const NF_DEV_CSS3:        &str = "\u{e749}";

// ─── Seti UI (nf-seti-*) ────────────────────────────────────────────────────

pub const NF_SETI_CONFIG:     &str = "\u{e5fc}";
pub const NF_SETI_TOML:       &str = "\u{e6b2}";
pub const NF_SETI_JSON:       &str = "\u{e60b}";
pub const NF_SETI_MARKDOWN:   &str = "\u{e73e}";
pub const NF_SETI_ORG:        &str = "\u{e633}";
pub const NF_SETI_WASM:       &str = "\u{e6a1}";

// ─── Custom / Linux (nf-linux-*) ────────────────────────────────────────────

pub const NF_LINUX_NIX:       &str = "\u{f313}";

// ─── Material Design (nf-md-*) ──────────────────────────────────────────────

pub const NF_MD_BINARY:       &str = "\u{f471}";
pub const NF_MD_ARCH:         &str = "\u{e266}";
pub const NF_MD_KERNEL:       &str = "\u{e615}";
pub const NF_MD_PICTURE:      &str = "\u{f02ef}";
pub const NF_MD_DOCUMENT:     &str = "\u{f09ee}";
pub const NF_MD_PUBLIC:       &str = "\u{f151f}";
pub const NF_MD_TEMP:         &str = "\u{f0403}";
pub const NF_MD_SSH:          &str = "\u{f12c0}";
pub const NF_MD_RAM:          &str = "\u{f0e4}";

// ─── Powerline (nf-ple-*) ───────────────────────────────────────────────────

pub const NF_PLE_LEFT_HARD:   &str = "\u{e0b0}";
pub const NF_PLE_RIGHT_HARD:  &str = "\u{e0b2}";
pub const NF_PLE_LEFT_SOFT:   &str = "\u{e0b1}";
pub const NF_PLE_RIGHT_SOFT:  &str = "\u{e0b3}";

// ─── Misc Unicode ───────────────────────────────────────────────────────────

pub const DEGREE_SIGN:        &str = "\u{00b0}";
pub const BOX_HORIZONTAL:     char = '\u{2500}';
