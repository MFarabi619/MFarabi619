use alloc::{format, string::{String, ToString}, vec, vec::Vec};

use ratatui::{
    Frame,
    layout::{Constraint, Layout, Rect},
    style::{Style, Stylize},
    text::{Line, Span},
    widgets::{Block, Clear, Paragraph},
};

use crate::{app::App, ui::PANELS};

const STATIC_KEYS: &[(&str, &str)] = &[
    ("0",                  "focus detail pane (press again to cycle tabs)"),
    ("[ / ]",              "previous / next detail tab"),
    ("h  ←  Shift+Tab",    "previous panel / leave detail focus"),
    ("l  →  Tab",          "next panel / leave detail focus"),
    ("",                   ""),
    ("j  ↓",               "move down within panel"),
    ("k  ↑",               "move up within panel"),
    ("g  /  G",            "jump to start / end of list"),
    ("",                   ""),
    ("@",                  "open command-log actions"),
    ("t",                  "cycle theme"),
    ("q",                  "quit"),
    ("Esc",                "close popup / leave detail or Status focus"),
];

pub fn render_help(frame: &mut Frame, app: &App) {
    let theme = app.theme();
    let popup_area = centered_rect(64, 72, frame.area());

    frame.render_widget(Clear, popup_area);

    let block = Block::bordered()
        .border_style(Style::new().fg(theme.accent))
        .title(Span::raw(" ? Help · keyboard shortcuts ").fg(theme.accent).bold());
    let inner_area = block.inner(popup_area);
    frame.render_widget(block, popup_area);

    let mut entries: Vec<(String, String)> = vec![
        ("?".into(), "toggle this help popup".into()),
        ("".into(), "".into()),
    ];
    for (i, panel) in PANELS.iter().enumerate() {
        entries.push((
            format!("{}", i + 1),
            format!("focus {}", panel.label()),
        ));
    }
    for (key, description) in STATIC_KEYS {
        entries.push(((*key).into(), (*description).into()));
    }

    let lines: Vec<Line<'static>> = entries
        .into_iter()
        .map(|(key, description)| {
            if key.is_empty() && description.is_empty() {
                Line::from("")
            } else {
                Line::from(vec![
                    Span::raw(format!(" {key:<22} ")).fg(theme.accent).bold(),
                    Span::raw(description).fg(theme.label),
                ])
            }
        })
        .collect();

    frame.render_widget(Paragraph::new(lines), inner_area);
}

fn centered_rect(percent_x: u16, percent_y: u16, area: Rect) -> Rect {
    let vertical = Layout::vertical([
        Constraint::Percentage((100 - percent_y) / 2),
        Constraint::Percentage(percent_y),
        Constraint::Percentage((100 - percent_y) / 2),
    ])
    .areas::<3>(area)[1];

    Layout::horizontal([
        Constraint::Percentage((100 - percent_x) / 2),
        Constraint::Percentage(percent_x),
        Constraint::Percentage((100 - percent_x) / 2),
    ])
    .areas::<3>(vertical)[1]
}
