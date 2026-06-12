use alloc::{vec, vec::Vec};

use ratatui::{
    Frame,
    layout::Rect,
    macros::line,
    style::{Style, Stylize},
    text::Line,
    widgets::{Block, Paragraph, Wrap},
};

use crate::tui::state::App;

const TIPS: &[&str] = &[
    "Focus panes with mouse, or numbers [0-5]. Press the same number again to cycle its tabs.",
    "Press [/] to cycle the active detail tab from any left pane.",
    "Esc leaves Status focus so lazyzephyr hotkeys work again.",
    "The chip icon's color tracks live serial status — green is good.",
    "Status's Devices tab will eventually show parsed `device list` output from the Zephyr shell.",
];

pub fn render(frame: &mut Frame, area: Rect, app: &App) {
    let theme = app.theme();
    let border_color = if app.command_log_focused {
        theme.accent
    } else {
        theme.border
    };

    let chrome = if app.command_log_focused { theme.accent } else { theme.label };
    let title = line!["[".fg(chrome), "@".fg(chrome).bold(), "]─".fg(chrome), "Command log".fg(chrome)];
    let block = Block::bordered()
        .border_type(theme.border_type)
        .border_style(Style::new().fg(border_color))
        .title(title);
    let inner = block.inner(area);
    frame.render_widget(block, area);
    if inner.height == 0 {
        return;
    }

    let tip = TIPS[(app.frame_tick as usize / 600) % TIPS.len()];

    let mut lines: Vec<Line<'static>> = vec![
        line!["Random tip: ".fg(theme.warning).bold(), tip.fg(theme.tiers[0])],
    ];

    if !app.command_log_entries.is_empty() {
        lines.push(Line::from(""));
        for entry in &app.command_log_entries {
            lines.push(line![entry.action.clone().fg(theme.warning).bold()]);
            lines.push(line!["  ".fg(theme.label), entry.command.clone().fg(theme.tiers[0])]);
        }
    }

    frame.render_widget(Paragraph::new(lines).wrap(Wrap { trim: false }), inner);
}
