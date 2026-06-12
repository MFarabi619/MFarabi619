use alloc::{string::String, vec::Vec};

use ratatui::{Frame, layout::Rect};

use crate::tui::{keybindings::Binding, input::Key, state::App, widgets::FilteredListState};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PanelTag {
    Status,
    Mcumgr,
    Kernel,
    Analyze,
    Wip,
}

#[derive(Debug, Default)]
pub struct PanelState {
    pub list:       FilteredListState,
    pub detail_tab: usize,
    pub list_tab:   usize,
}

pub trait Panel: Sync {
    fn tag(&self) -> PanelTag;
    fn label(&self) -> &'static str;
    fn detail_tabs(&self, _app: &App) -> Vec<&'static str> { alloc::vec!["Logs"] }
    fn inner_tabs(&self) -> &'static [&'static str] { &[] }
    fn list_len(&self, _app: &App) -> usize { 0 }
    fn current_name(&self, _app: &App) -> String { String::new() }
    fn bindings(&self, _app: &App) -> Vec<Binding> { Vec::new() }
    fn render_list  (&self, frame: &mut Frame, area: Rect, app: &mut App, focused: bool);
    fn render_detail(&self, _f: &mut Frame, _a: Rect, _app: &mut App, _tab: &str) {}
    fn scroll_detail(&self, _app: &mut App, _lines: isize) {}
    fn on_action_key(&self, app: &mut App, key: Key) -> bool {
        let bindings = self.bindings(app);
        for binding in bindings {
            if binding.matches(key) {
                if let Some(handler) = binding.handler {
                    handler(app);
                    return true;
                }
            }
        }
        false
    }
}
