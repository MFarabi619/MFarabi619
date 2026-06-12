use alloc::{format, string::{String, ToString}, vec::Vec};

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
    render::{panel_title, selection_style, selection_symbol, titled_list_block},
    state::App,
};

pub struct StatusPanel;

impl StatusPanel {
    pub fn selected_action(&self, app: &App) -> Option<usize> {
        let idx = app.state_of(self.tag()).list.selected().unwrap_or(0);
        if idx < app.build.actions().len() { Some(idx) } else { None }
    }
}

impl Panel for StatusPanel {
    fn tag(&self) -> PanelTag { PanelTag::Status }
    fn label(&self) -> &'static str { "Status" }

    fn detail_tabs(&self, app: &App) -> Vec<&'static str> {
        match self.selected_action(app) {
            Some(idx) => app.build.actions().get(idx).map(|a| {
                if a.tabs.is_empty() { alloc::vec![a.name] } else { a.tabs.to_vec() }
            }).unwrap_or_else(|| alloc::vec!["(no action)"]),
            None => alloc::vec!["(no actions)"],
        }
    }

    fn list_len(&self, app: &App) -> usize {
        app.build.actions().len()
    }

    fn current_name(&self, app: &App) -> String {
        self.selected_action(app)
            .and_then(|idx| app.build.actions().get(idx).map(|a| a.name.into()))
            .unwrap_or_default()
    }

    fn bindings(&self, _app: &App) -> Vec<crate::tui::keybindings::Binding> {
        use crate::tui::keybindings::{ACTION_TAG, Binding};
        alloc::vec![
            Binding::new(&["r"], "refresh / re-run command").footer().short("Refresh").tag(ACTION_TAG).handler(refresh_build),
        ]
    }

    fn render_list(&self, frame: &mut Frame, area: Rect, app: &mut App, focused: bool) {
        let theme    = *app.theme();
        let title    = panel_title(&theme, app.index_of(self.tag()) + 1, self.label(), focused, false, app.config.gui.show_panel_jumps);
        let total    = self.list_len(app);
        let selected = app.state_of(self.tag()).list.selected();
        let block    = titled_list_block(&theme, title, focused, selected, total);

        let actions = app.build.actions();
        let items: Vec<ListItem> = actions.iter().map(|action| {
            ListItem::new(line![
                format!("{} ", action.icon).fg(theme.muted),
                action.name.to_string().fg(theme.foreground),
            ])
        }).collect();

        let list = List::new(items).block(block)
            .highlight_style(selection_style(&theme, focused))
            .highlight_symbol(selection_symbol(focused));
        let state = &mut app.state_of_mut(self.tag()).list.list;
        frame.render_stateful_widget(list, area, state);
    }

    fn render_detail(&self, frame: &mut Frame, area: Rect, app: &mut App, tab: &str) {
        let theme = *app.theme();
        let Some(action_idx) = self.selected_action(app) else {
            frame.render_widget(Paragraph::new("no build actions configured".fg(theme.label)), area);
            return;
        };
        let Some(action) = app.build.actions().get(action_idx).cloned() else {
            frame.render_widget(Paragraph::new("no build action".fg(theme.label)), area);
            return;
        };
        let tab_idx = if action.tabs.is_empty() {
            0
        } else {
            action.tabs.iter().position(|t| *t == tab).unwrap_or(0)
        };
        if let Some(cmd) = app.build.ensure_spawned(action_idx, tab_idx) {
            let label = if action.tabs.is_empty() {
                format!("Status: {}", action.name)
            } else {
                format!("Status: {} / {}", action.name, action.tabs[tab_idx])
            };
            app.log_command(label, cmd);
        }
        app.build.render(action_idx, tab_idx, frame, area, &theme);
        let _ = Line::raw("");
    }

    fn scroll_detail(&self, app: &mut App, lines: isize) {
        let Some(action_idx) = self.selected_action(app) else { return; };
        let tab_idx = active_build_tab_idx(app, action_idx);
        app.build.scroll(action_idx, tab_idx, lines);
    }
}

fn refresh_build(app: &mut App) {
    let panel = StatusPanel;
    if let Some(action_idx) = panel.selected_action(app) {
        let tab_idx = active_build_tab_idx(app, action_idx);
        app.build.refresh(action_idx, tab_idx);
    }
}

fn active_build_tab_idx(app: &App, action_idx: usize) -> usize {
    let detail_tab = app.state_of(PanelTag::Status).detail_tab;
    let Some(action) = app.build.actions().get(action_idx) else { return 0; };
    if action.tabs.is_empty() { 0 } else { detail_tab.min(action.tabs.len().saturating_sub(1)) }
}
