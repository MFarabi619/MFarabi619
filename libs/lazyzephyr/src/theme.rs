use core::str::FromStr;

use ratatui::{
    style::{
        Color,
        palette::tailwind::{AMBER, BLUE, CYAN, EMERALD, LIME, ORANGE, RED, ROSE, SLATE, STONE},
    },
    widgets::BorderType,
};

#[derive(Clone, Copy)]
pub struct Theme {
    pub border:                        Color,
    pub accent:                        Color,
    pub options_text:                  Color,
    pub searching_active_border:       Color,
    pub foreground:                    Color,
    pub label:                         Color,
    pub muted:                         Color,
    pub value:                         Color,
    pub success:                       Color,
    pub warning:                       Color,
    pub error:                         Color,
    pub tiers:                         [Color; 5],
    pub selection_background:          Color,
    pub selection_background_inactive: Color,
    pub selection_foreground:          Color,
    pub border_type:                   BorderType,
}

impl Theme {
    pub fn tier_for_ratio(&self, ratio: f64) -> Color {
        let clamped = ratio.clamp(0.0, 0.9999);
        let bucket = (clamped * 5.0) as usize;
        self.tiers[bucket.min(4)]
    }
}

pub const DEFAULT: Theme = Theme {
    border:                        SLATE.c700,
    accent:                        EMERALD.c400,
    options_text:                  BLUE.c400,
    searching_active_border:       CYAN.c400,
    foreground:                    SLATE.c200,
    label:                         SLATE.c500,
    muted:                         SLATE.c400,
    value:                         SLATE.c100,
    success:                       EMERALD.c400,
    warning:                       AMBER.c400,
    error:                         ROSE.c400,
    tiers:                         [LIME.c300, EMERALD.c400, AMBER.c400, ORANGE.c400, ROSE.c500],
    selection_background:          BLUE.c800,
    selection_background_inactive: Color::Reset,
    selection_foreground:          SLATE.c50,
    border_type:                   BorderType::Rounded,
};

pub const GRUVBOX: Theme = Theme {
    border:                        STONE.c600,
    accent:                        SLATE.c400,
    options_text:                  STONE.c200,
    searching_active_border:       AMBER.c400,
    foreground:                    STONE.c300,
    label:                         STONE.c500,
    muted:                         STONE.c400,
    value:                         STONE.c200,
    success:                       LIME.c400,
    warning:                       AMBER.c400,
    error:                         RED.c400,
    tiers:                         [LIME.c400, EMERALD.c400, AMBER.c400, ORANGE.c400, RED.c500],
    selection_background:          STONE.c700,
    selection_background_inactive: Color::Reset,
    selection_foreground:          STONE.c100,
    border_type:                   BorderType::Rounded,
};

pub fn preset_by_name(name: Option<&str>) -> Theme {
    match name {
        Some("default") => DEFAULT,
        _               => GRUVBOX,
    }
}

pub fn resolve(gui: &crate::config::GuiConfig) -> Theme {
    use crate::tui::style::color::parse_color;
    let mut theme = preset_by_name(gui.theme.preset.as_deref());
    let cfg = &gui.theme;
    if let Some(c) = parse_color(&cfg.active_border_color)                 { theme.accent                        = c; }
    if let Some(c) = parse_color(&cfg.inactive_border_color)               { theme.border                        = c; }
    if let Some(c) = parse_color(&cfg.searching_active_border_color)       { theme.searching_active_border       = c; }
    if let Some(c) = parse_color(&cfg.options_text_color)                  { theme.options_text                  = c; }
    if let Some(c) = parse_color(&cfg.selected_line_bg_color)              { theme.selection_background          = c; }
    if let Some(c) = parse_color(&cfg.inactive_view_selected_line_bg_color){ theme.selection_background_inactive = c; }
    if let Some(c) = parse_color(&cfg.default_fg_color)                    { theme.foreground           = c; }
    if let Some(c) = parse_color(&cfg.success_color)                       { theme.success              = c; }
    if let Some(c) = parse_color(&cfg.warning_color)                       { theme.warning              = c; }
    if let Some(c) = parse_color(&cfg.error_color)                         { theme.error                = c; }
    if let Some(c) = parse_color(&cfg.label_color)                         { theme.label                = c; }
    if let Some(c) = parse_color(&cfg.value_color)                         { theme.value                = c; }
    for (i, tier) in cfg.tier_colors.iter().enumerate().take(5) {
        if let Some(c) = parse_color(tier) { theme.tiers[i] = c; }
    }
    if !gui.border.is_empty() {
        if let Ok(bt) = BorderType::from_str(&gui.border) {
            theme.border_type = bt;
        }
    }
    theme
}
