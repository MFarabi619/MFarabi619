use alloc::{string::String, vec::Vec};

use ratatui::{Frame, layout::Rect};

use crate::{app::App, input::Key, state::ListView};

pub type FooterAction = (&'static str, &'static str);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PanelTag {
    Status,
    Threads,
    HeapPools,
    Network,
    Events,
}

#[derive(Debug, Default)]
pub struct PanelState {
    pub list:       ListView,
    pub detail_tab: usize,
    pub list_tab:   usize,
    pub filter:     String,
}

pub trait Panel: Sync {
    fn tag(&self) -> PanelTag;
    fn label(&self) -> &'static str;
    fn detail_tabs(&self, _app: &App) -> Vec<&'static str> { alloc::vec!["Logs"] }
    fn inner_tabs(&self) -> &'static [&'static str] { &[] }
    fn list_len(&self, _app: &App) -> usize { 0 }
    fn current_name(&self, _app: &App) -> String { String::new() }
    fn footer_actions(&self, _app: &App) -> Vec<FooterAction> { Vec::new() }
    fn supports_filter(&self) -> bool { false }
    fn render_list  (&self, frame: &mut Frame, area: Rect, app: &mut App, focused: bool);
    fn render_detail(&self, _f: &mut Frame, _a: Rect, _app: &mut App, _tab: &str) {}
    fn scroll_detail(&self, _app: &mut App, _lines: isize) {}
    fn on_action_key(&self, _app: &mut App, _key: Key) -> bool { false }
}
