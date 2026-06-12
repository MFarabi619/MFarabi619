use alloc::{string::String, vec::Vec};

use serde::{Deserialize, Serialize};

#[cfg(feature = "schema")]
use schemars::JsonSchema;

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "schema", derive(JsonSchema))]
#[serde(default, rename_all = "camelCase")]
pub struct UserConfig {
    pub gui:                            GuiConfig,
    pub mcumgr:                         McumgrConfig,
    pub confirm_on_quit:                bool,
    pub quit_on_top_level_return:       bool,
    pub disable_startup_popups:         bool,
    pub services:                       ServicesConfig,
    pub not_in_workspace:               NotInWorkspace,
    pub prompt_to_return_from_subprocess: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "schema", derive(JsonSchema))]
#[serde(default, rename_all = "camelCase")]
pub struct McumgrConfig {
    pub address:    String,
    pub timeout_ms: u64,
}

impl Default for McumgrConfig {
    fn default() -> Self {
        Self { address: String::new(), timeout_ms: 1000 }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "schema", derive(JsonSchema))]
#[serde(default, rename_all = "camelCase")]
pub struct GuiConfig {
    pub theme:                     ThemeConfig,
    pub border:                    String,
    pub mouse_events:              bool,
    pub show_command_log:          bool,
    pub command_log_size:          u16,
    pub show_bottom_line:          bool,
    pub show_panel_jumps:          bool,
    pub side_panel_width:          f64,
    pub expand_focused_side_panel: bool,
    pub scroll_height:             u16,
    pub nerd_fonts_version:        String,
    pub filter_mode:               String,
    pub fuzzy_search:              bool,
    pub spinner:                   SpinnerConfig,
}

impl Default for GuiConfig {
    fn default() -> Self {
        Self {
            theme:                     ThemeConfig::default(),
            border:                    String::from("rounded"),
            mouse_events:              true,
            show_command_log:          true,
            command_log_size:          8,
            show_bottom_line:          true,
            show_panel_jumps:          true,
            side_panel_width:          0.3333,
            expand_focused_side_panel: true,
            scroll_height:             2,
            nerd_fonts_version:        String::new(),
            filter_mode:               String::new(),
            fuzzy_search:              true,
            spinner:                   SpinnerConfig::default(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "schema", derive(JsonSchema))]
#[serde(default, rename_all = "camelCase")]
pub struct SpinnerConfig {
    pub frames: Vec<String>,
    pub rate:   u16,
}

impl Default for SpinnerConfig {
    fn default() -> Self {
        Self { frames: Vec::new(), rate: 50 }
    }
}

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "schema", derive(JsonSchema))]
#[serde(default, rename_all = "camelCase")]
pub struct ThemeConfig {
    pub preset:                              Option<String>,
    pub active_border_color:                 Vec<String>,
    pub inactive_border_color:               Vec<String>,
    pub searching_active_border_color:       Vec<String>,
    pub options_text_color:                  Vec<String>,
    pub selected_line_bg_color:              Vec<String>,
    pub inactive_view_selected_line_bg_color: Vec<String>,
    pub default_fg_color:                    Vec<String>,
    pub success_color:                       Vec<String>,
    pub warning_color:                       Vec<String>,
    pub error_color:                         Vec<String>,
    pub label_color:                         Vec<String>,
    pub value_color:                         Vec<String>,
    pub tier_colors:                         Vec<Vec<String>>,
}

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "schema", derive(JsonSchema))]
#[serde(default, rename_all = "camelCase")]
pub struct ServicesConfig {
    pub entries: Vec<(String, String)>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[cfg_attr(feature = "schema", derive(JsonSchema))]
#[serde(rename_all = "lowercase")]
pub enum NotInWorkspace {
    #[default]
    Prompt,
    Create,
    Skip,
    Quit,
}
