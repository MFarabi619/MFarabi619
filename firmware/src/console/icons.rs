//! Centralized Nerd Font glyph registry.
//!
//! Names match the Nerd Font cheat sheet: https://www.nerdfonts.com/cheat-sheet
//! Format: NF_{source}_{name} in SCREAMING_SNAKE_CASE.

// ─── Font Awesome (nf-fa-*) ────────────────────────────────────────────────────

pub const NF_FA_FILE: &str = "\u{f15b}"; // nf-fa-file
pub const NF_FA_FILE_TEXT: &str = "\u{f15c}"; // nf-fa-file_text_o
pub const NF_FA_FILE_IMAGE: &str = "\u{f1c5}"; // nf-fa-file_image_o
pub const NF_FA_FOLDER: &str = "\u{f07b}"; // nf-fa-folder
pub const NF_FA_FOLDER_OPEN: &str = "\u{f07c}"; // nf-fa-folder-open

pub const NF_FA_HOME: &str = "\u{f015}"; // nf-fa-home
pub const NF_FA_LOCK: &str = "\u{f023}"; // nf-fa-lock
pub const NF_FA_CLOCK: &str = "\u{f017}"; // nf-fa-clock_o
pub const NF_FA_DATABASE: &str = "\u{f1c0}"; // nf-fa-database
pub const NF_FA_GLOBE: &str = "\u{f0ac}"; // nf-fa-globe
pub const NF_FA_SERVER: &str = "\u{f233}"; // nf-fa-server
pub const NF_FA_PLUG: &str = "\u{f1e6}"; // nf-fa-plug
pub const NF_FA_WIFI: &str = "\u{f1eb}"; // nf-fa-wifi
pub const NF_FA_COG: &str = "\u{f085}"; // nf-fa-cog (alias: gear)
pub const NF_FA_BOLT: &str = "\u{f0e7}"; // nf-fa-bolt
pub const NF_FA_HDD: &str = "\u{f0a0}"; // nf-fa-hdd_o
pub const NF_FA_LEAF: &str = "\u{f06c}"; // nf-fa-leaf
pub const NF_FA_THERMOMETER: &str = "\u{f2c9}"; // nf-fa-thermometer
pub const NF_FA_TINT: &str = "\u{f043}"; // nf-fa-tint
pub const NF_FA_SITEMAP: &str = "\u{f1e0}"; // nf-fa-sitemap
pub const NF_FA_MICROCHIP: &str = "\u{f2db}"; // nf-fa-microchip
pub const NF_FA_SIGNAL: &str = "\u{f2c8}"; // nf-fa-signal (alias: wifi_signal)
pub const NF_FA_DOWNLOAD: &str = "\u{f498}"; // nf-fa-cloud_download (approx)
pub const NF_FA_TERMINAL: &str = "\u{f120}"; // nf-fa-terminal
pub const NF_FA_DESKTOP: &str = "\u{f108}"; // nf-fa-desktop
pub const NF_FA_MEMORY: &str = "\u{f538}"; // nf-fa-memory

// ─── Dev Icons (nf-dev-*) ──────────────────────────────────────────────────────

pub const NF_DEV_RUST: &str = "\u{e7a8}"; // nf-dev-rust
pub const NF_DEV_HTML5: &str = "\u{e736}"; // nf-dev-html5
pub const NF_DEV_JAVASCRIPT: &str = "\u{e74e}"; // nf-dev-javascript
pub const NF_DEV_CSS3: &str = "\u{e749}"; // nf-dev-css3

// ─── Seti UI (nf-seti-*) ──────────────────────────────────────────────────────

pub const NF_SETI_CONFIG: &str = "\u{e5fc}"; // nf-seti-config
pub const NF_SETI_TOML: &str = "\u{e6b2}"; // nf-seti-toml (approx)
pub const NF_SETI_JSON: &str = "\u{e60b}"; // nf-seti-json
pub const NF_SETI_MARKDOWN: &str = "\u{e73e}"; // nf-seti-markdown
pub const NF_SETI_ORG: &str = "\u{e633}"; // nf-seti-org (approx: emacs)
pub const NF_SETI_WASM: &str = "\u{e6a1}"; // nf-seti-wasm (approx)

// ─── Custom / Linux (nf-linux-*) ───────────────────────────────────────────────

pub const NF_LINUX_NIX: &str = "\u{f313}"; // nf-linux-nixos

// ─── Material Design (nf-md-*) ─────────────────────────────────────────────────

pub const NF_MD_BINARY: &str = "\u{f471}"; // nf-md-file_binary (approx)
pub const NF_MD_ARCH: &str = "\u{e266}"; // nf-md-chip (approx)
pub const NF_MD_KERNEL: &str = "\u{e615}"; // nf-md-penguin (approx)
pub const NF_MD_PICTURE: &str = "\u{F02EF}"; // nf-md-image (SPA)
pub const NF_MD_DOCUMENT: &str = "\u{F09EE}"; // nf-md-file_document (SPA)
pub const NF_MD_PUBLIC: &str = "\u{F151F}"; // nf-md-account_group (SPA)
pub const NF_MD_TEMP: &str = "\u{F0403}"; // nf-md-folder_clock (SPA)
pub const NF_MD_SSH: &str = "\u{F12C0}"; // nf-md-ssh (SPA)
pub const NF_MD_RAM: &str = "\u{f0e4}"; // nf-md-speedometer (approx)

// ─── Powerline (nf-ple-*) ──────────────────────────────────────────────────────

pub const NF_PLE_LEFT_HARD: &str = "\u{e0b0}"; // nf-ple-left_half_circle_thick
pub const NF_PLE_RIGHT_HARD: &str = "\u{e0b2}"; // nf-ple-right_half_circle_thick
pub const NF_PLE_LEFT_SOFT: &str = "\u{e0b1}"; // nf-ple-left_half_circle_thin
pub const NF_PLE_RIGHT_SOFT: &str = "\u{e0b3}"; // nf-ple-right_half_circle_thin

// ─── Misc Unicode ──────────────────────────────────────────────────────────────

pub const DEGREE_SIGN: &str = "\u{00b0}"; // ° (not a Nerd Font glyph)
pub const BOX_HORIZONTAL: char = '\u{2500}'; // ─ (box drawing)
