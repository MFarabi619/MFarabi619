use alloc::{format, string::{String, ToString}, vec, vec::Vec};

use ratatui::{
    Frame,
    layout::{Constraint, Rect},
    macros::line,
    style::{Modifier, Style, Stylize},
    text::Line,
    widgets::{Cell, List, ListItem, Paragraph, Row, Table, Wrap},
};

use crate::tui::{
    panel::{Panel, PanelTag},
    render::{overlay_panel_tabs, panel_title, selection_style, selection_symbol, titled_list_block},
    state::App,
};

const TABS: &[&str] = &["Header", "List"];
const TAB_LIST: usize = 1;

fn filtered_project_idxs(app: &App) -> Vec<usize> {
    let filter = app.state_of(PanelTag::Analyze).list.filter.to_ascii_lowercase();
    app.workspace.projects.iter().enumerate()
        .filter(|(_, p)| {
            if filter.is_empty() { return true; }
            p.name.to_ascii_lowercase().contains(&filter)
                || p.path.to_ascii_lowercase().contains(&filter)
                || p.url.to_ascii_lowercase().contains(&filter)
        })
        .map(|(i, _)| i)
        .collect()
}

pub struct AnalyzePanel;

impl Panel for AnalyzePanel {
    fn tag(&self) -> PanelTag { PanelTag::Analyze }
    fn label(&self) -> &'static str { "Analyze" }
    fn inner_tabs(&self) -> &'static [&'static str] { TABS }

    fn detail_tabs(&self, app: &App) -> Vec<&'static str> {
        match app.state_of(self.tag()).list_tab {
            TAB_LIST => vec!["Project"],
            _        => vec!["Header"],
        }
    }

    fn list_len(&self, app: &App) -> usize {
        match app.state_of(self.tag()).list_tab {
            TAB_LIST => filtered_project_idxs(app).len(),
            _        => 1,
        }
    }

    fn current_name(&self, app: &App) -> String {
        let state = app.state_of(self.tag());
        let cursor = state.list.selected().unwrap_or(0);
        match state.list_tab {
            TAB_LIST => {
                let idxs = filtered_project_idxs(app);
                idxs.get(cursor).and_then(|i| app.workspace.projects.get(*i)).map(|p| p.name.clone()).unwrap_or_default()
            }
            _        => {
                let basename = app.elf_info.path.rsplit('/').next().unwrap_or(app.elf_info.path.as_str());
                if basename.is_empty() { "no elf".into() } else { basename.into() }
            }
        }
    }

    fn render_list(&self, frame: &mut Frame, area: Rect, app: &mut App, focused: bool) {
        let theme    = *app.theme();
        let title    = panel_title(&theme, app.index_of(self.tag()) + 1, self.label(), focused, false, app.config.gui.show_panel_jumps);
        let total    = self.list_len(app);
        let selected = app.state_of(self.tag()).list.selected();
        let block    = titled_list_block(&theme, title, focused, selected, total);

        let active     = app.state_of(self.tag()).list_tab;
        let panel_idx  = app.index_of(self.tag()) + 1;
        let show_jumps = app.config.gui.show_panel_jumps;

        let items: Vec<ListItem> = match active {
            TAB_LIST => filtered_project_idxs(app).into_iter().filter_map(|i| app.workspace.projects.get(i)).map(|project| {
                ListItem::new(line![
                    "\u{f02d} ".fg(theme.accent),
                    project.name.clone().fg(theme.foreground),
                    format!(" \u{b7} {}", project.path).fg(theme.muted),
                ])
            }).collect(),
            _ => {
                let elf = &app.elf_info;
                let dot_color = if elf.loaded() { theme.success }
                                else if elf.error.is_some() { theme.error }
                                else { theme.label };
                let basename = elf.path.rsplit('/').next().unwrap_or(elf.path.as_str());
                let label = if basename.is_empty() { "no elf" } else { basename };
                vec![ListItem::new(line![
                    "\u{f1c6} ".fg(dot_color),
                    label.to_string().fg(theme.foreground),
                ])]
            }
        };

        let list = List::new(items).block(block)
            .highlight_style(selection_style(&theme, focused))
            .highlight_symbol(selection_symbol(focused));
        let state = &mut app.state_of_mut(self.tag()).list.list;
        frame.render_stateful_widget(list, area, state);

        overlay_panel_tabs(frame, area, &theme, panel_idx, TABS, active, focused, show_jumps);
    }

    fn render_detail(&self, frame: &mut Frame, area: Rect, app: &mut App, _tab: &str) {
        let theme = *app.theme();
        let state = app.state_of(self.tag());
        match state.list_tab {
            TAB_LIST => render_project_detail(frame, area, app),
            _        => render_header_detail(frame, area, app, &theme),
        }
    }
}

fn render_project_detail(frame: &mut Frame, area: Rect, app: &App) {
    let theme = *app.theme();
    let cursor = app.state_of(PanelTag::Analyze).list.selected().unwrap_or(0);
    let idxs   = filtered_project_idxs(app);
    let Some(project) = idxs.get(cursor).and_then(|i| app.workspace.projects.get(*i)) else {
        frame.render_widget(Paragraph::new("no project selected".fg(theme.label)), area);
        return;
    };
    let lines: Vec<Line<'static>> = vec![
        line![format!("{:<14}", "name").fg(theme.label),     project.name.clone().fg(theme.value).bold()],
        line![format!("{:<14}", "path").fg(theme.label),     project.path.clone().fg(theme.value).bold()],
        line![format!("{:<14}", "revision").fg(theme.label), project.revision.clone().fg(theme.value).bold()],
        line![format!("{:<14}", "url").fg(theme.label),      project.url.clone().fg(theme.value).bold()],
    ];
    frame.render_widget(Paragraph::new(lines).wrap(Wrap { trim: false }), area);
}

fn render_header_detail(frame: &mut Frame, area: Rect, app: &App, theme: &crate::theme::Theme) {
    let elf = &app.elf_info;
    if let Some(error) = &elf.error {
        frame.render_widget(
            Paragraph::new(vec![
                Line::from(elf.path.clone().fg(theme.label)),
                Line::from(""),
                Line::from(error.clone().fg(theme.error)),
            ]).wrap(Wrap { trim: false }),
            area,
        );
        return;
    }
    if elf.headers.is_empty() {
        frame.render_widget(
            Paragraph::new(Line::from("no elf loaded".fg(theme.label))),
            area,
        );
        return;
    }
    let rows: Vec<Row> = elf.headers.iter().map(|(k, v)| {
        Row::new(vec![
            Cell::from(k.clone()).style(Style::new().fg(theme.label)),
            Cell::from(v.clone()).style(Style::new().fg(theme.value).add_modifier(Modifier::BOLD)),
        ])
    }).collect();
    let table = Table::new(rows, [Constraint::Length(34), Constraint::Fill(1)]).column_spacing(1);
    frame.render_widget(table, area);
}
