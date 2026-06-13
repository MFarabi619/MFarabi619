use alloc::{format, string::{String, ToString}, vec::Vec};

use ratatui::{
    Frame,
    layout::Rect,
    macros::line,
    style::Stylize,
    text::Line,
    widgets::{List, ListItem, Paragraph, Wrap},
};

use crate::tui::{
    panel::{Panel, PanelTag},
    render::{panel_title, selection_style, selection_symbol, titled_list_block},
    state::App,
};

struct StatusEntry {
    name: &'static str,
    icon: &'static str,
}

const ENTRIES: &[StatusEntry] = &[
    StatusEntry { name: "menuconfig", icon: "\u{f0493}" },
    StatusEntry { name: "workspace",  icon: "\u{f0c1d}" },
];

const IDX_MENUCONFIG: usize = 0;
const IDX_WORKSPACE:  usize = 1;

pub struct StatusPanel;

impl StatusPanel {
    pub fn selected_action(&self, app: &App) -> Option<usize> {
        let idx = app.state_of(self.tag()).list.selected().unwrap_or(0);
        if idx < ENTRIES.len() { Some(idx) } else { None }
    }
}

impl Panel for StatusPanel {
    fn tag(&self) -> PanelTag { PanelTag::Status }
    fn label(&self) -> &'static str { "Status" }

    fn detail_tabs(&self, app: &App) -> Vec<&'static str> {
        match self.selected_action(app) {
            Some(idx) => ENTRIES.get(idx).map(|e| alloc::vec![e.name]).unwrap_or_else(|| alloc::vec!["(none)"]),
            None      => alloc::vec!["(none)"],
        }
    }

    fn list_len(&self, _app: &App) -> usize {
        ENTRIES.len()
    }

    fn current_name(&self, app: &App) -> String {
        self.selected_action(app)
            .and_then(|idx| ENTRIES.get(idx).map(|e| e.name.into()))
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

        let items: Vec<ListItem> = ENTRIES.iter().map(|entry| {
            ListItem::new(line![
                format!("{} ", entry.icon).fg(theme.muted),
                entry.name.to_string().fg(theme.foreground),
            ])
        }).collect();

        let list = List::new(items).block(block)
            .highlight_style(selection_style(&theme, focused))
            .highlight_symbol(selection_symbol(focused));
        let state = &mut app.state_of_mut(self.tag()).list.list;
        frame.render_stateful_widget(list, area, state);
    }

    fn render_detail(&self, frame: &mut Frame, area: Rect, app: &mut App, _tab: &str) {
        let theme = *app.theme();
        let Some(idx) = self.selected_action(app) else {
            frame.render_widget(Paragraph::new("no status entries configured".fg(theme.label)), area);
            return;
        };
        match idx {
            IDX_MENUCONFIG => {
                if let Some(cmd) = app.build.ensure_spawned(0, 0) {
                    app.log_command("Status: menuconfig", cmd);
                }
                app.build.render(0, 0, frame, area, &theme);
            }
            IDX_WORKSPACE => render_workspace(frame, area, app),
            _ => {}
        }
    }

    fn scroll_detail(&self, app: &mut App, lines: isize) {
        let Some(idx) = self.selected_action(app) else { return; };
        if idx == IDX_MENUCONFIG {
            app.build.scroll(0, 0, lines);
        }
    }
}

fn render_workspace(frame: &mut Frame, area: Rect, app: &App) {
    let theme = *app.theme();
    let entries = &app.workspace.config;
    if entries.is_empty() {
        frame.render_widget(Paragraph::new("west config unavailable \u{2014} `west config -l` returned nothing".fg(theme.label)), area);
        return;
    }
    let mut lines: Vec<Line<'static>> = Vec::with_capacity(entries.len() + 1);
    let mut current_section: Option<String> = None;
    for entry in entries {
        let (section, leaf) = entry.key.split_once('.').unwrap_or(("", entry.key.as_str()));
        let section_owned = section.to_string();
        if current_section.as_deref() != Some(section) {
            if current_section.is_some() { lines.push(Line::raw("")); }
            lines.push(Line::from(format!("[{section_owned}]").fg(theme.accent).bold()));
            current_section = Some(section_owned);
        }
        lines.push(line![
            format!("{:<14}", leaf).fg(theme.label),
            entry.value.clone().fg(theme.value).bold(),
        ]);
    }
    frame.render_widget(Paragraph::new(lines).wrap(Wrap { trim: false }), area);
}

fn refresh_build(app: &mut App) {
    let panel = StatusPanel;
    if let Some(idx) = panel.selected_action(app) {
        if idx == IDX_MENUCONFIG {
            app.build.refresh(0, 0);
        }
    }
}
