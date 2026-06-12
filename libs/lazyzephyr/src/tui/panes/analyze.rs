use alloc::{string::ToString, vec, vec::Vec};

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
    render::{panel_title, selection_style, selection_symbol, titled_list_block},
    state::App,
};

pub struct AnalyzePanel;

impl Panel for AnalyzePanel {
    fn tag(&self) -> PanelTag { PanelTag::Analyze }
    fn label(&self) -> &'static str { "Analyze" }
    fn detail_tabs(&self, _app: &App) -> Vec<&'static str> { vec!["Header"] }
    fn list_len(&self, _app: &App) -> usize { 1 }

    fn render_list(&self, frame: &mut Frame, area: Rect, app: &mut App, focused: bool) {
        let theme    = *app.theme();
        let title    = panel_title(&theme, app.index_of(self.tag()) + 1, self.label(), focused, false, app.config.gui.show_panel_jumps);
        let total    = self.list_len(app);
        let selected = app.state_of(self.tag()).list.selected();
        let block    = titled_list_block(&theme, title, focused, selected, total);

        let elf = &app.elf_info;
        let dot_color = if elf.loaded() { theme.success }
                        else if elf.error.is_some() { theme.error }
                        else { theme.label };
        let basename = elf.path.rsplit('/').next().unwrap_or(elf.path.as_str());
        let label = if basename.is_empty() { "no elf" } else { basename };

        let items = vec![ListItem::new(line![
            "\u{f1c6} ".fg(dot_color),
            label.to_string().fg(theme.foreground),
        ])];

        let list = List::new(items).block(block)
            .highlight_style(selection_style(&theme, focused))
            .highlight_symbol(selection_symbol(focused));
        let state = &mut app.state_of_mut(self.tag()).list.list;
        frame.render_stateful_widget(list, area, state);
    }

    fn render_detail(&self, frame: &mut Frame, area: Rect, app: &mut App, _tab: &str) {
        let theme = *app.theme();
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
}
