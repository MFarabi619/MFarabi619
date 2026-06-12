use alloc::{format, string::String, vec, vec::Vec};

use ratatui::{
    Frame,
    layout::Rect,
    macros::line,
    style::Stylize,
    text::Line,
    widgets::{List, ListItem, Paragraph},
};

use crate::tui::{
    panel::{Panel, PanelTag},
    render::{panel_title, placeholder_paragraph, selection_style, selection_symbol, titled_list_block},
    state::App,
};

const ENTRIES: &[(&str, &str)] = &[
    ("WIP", "\u{f0ad}"),
];

pub struct WipPanel;

impl Panel for WipPanel {
    fn tag(&self) -> PanelTag { PanelTag::Wip }
    fn label(&self) -> &'static str { "WIP" }
    fn detail_tabs(&self, _app: &App) -> Vec<&'static str> { vec!["WIP"] }
    fn list_len(&self, _app: &App) -> usize { ENTRIES.len() }

    fn current_name(&self, app: &App) -> String {
        let idx = app.state_of(self.tag()).list.selected().unwrap_or(0);
        ENTRIES.get(idx).map(|(label, _)| (*label).into()).unwrap_or_default()
    }

    fn render_list(&self, frame: &mut Frame, area: Rect, app: &mut App, focused: bool) {
        let theme    = *app.theme();
        let title    = panel_title(&theme, app.index_of(self.tag()) + 1, self.label(), focused, false, app.config.gui.show_panel_jumps);
        let total    = ENTRIES.len();
        let selected = app.state_of(self.tag()).list.selected();
        let block    = titled_list_block(&theme, title, focused, selected, total);
        let items: Vec<ListItem> = ENTRIES.iter().map(|(label, icon)| {
            ListItem::new(line![
                format!("{} ", icon).fg(theme.warning),
                (*label).fg(theme.foreground),
            ])
        }).collect();
        let list = List::new(items).block(block)
            .highlight_style(selection_style(&theme, focused))
            .highlight_symbol(selection_symbol(focused));
        let idx = app.index_of(self.tag());
        frame.render_stateful_widget(list, area, &mut app.states[idx].list.list);
    }

    fn render_detail(&self, frame: &mut Frame, area: Rect, app: &mut App, _tab: &str) {
        let theme = *app.theme();
        frame.render_widget(
            Paragraph::new(Line::from("Work in progress.".fg(theme.label))),
            area,
        );
        let _ = placeholder_paragraph;
    }
}
