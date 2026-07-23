#[cfg(all(CONFIG_DISPLAY, any(CONFIG_ILI9341, CONFIG_SH8601)))]
pub mod tui;
