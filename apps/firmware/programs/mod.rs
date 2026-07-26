#[cfg(all(
    CONFIG_DISPLAY,
    not(CONFIG_LVGL),
    any(CONFIG_ILI9341, CONFIG_SH8601)
))]
pub mod tui;

#[cfg(all(CONFIG_LVGL, CONFIG_ZENOH_PICO))]
pub mod teleop;
