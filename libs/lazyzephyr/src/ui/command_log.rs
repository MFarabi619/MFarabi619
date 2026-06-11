use alloc::{vec, vec::Vec};

use ratatui::{
    Frame,
    layout::Rect,
    style::{Style, Stylize},
    text::{Line, Span},
    widgets::{Block, Paragraph, Wrap},
};

use crate::app::App;

const TIPS: &[&str] = &[
    "Focus panes with mouse, or numbers [0-5]. Press the same number again to cycle its tabs.",
    "Press [/] to cycle the active detail tab from any left pane.",
    "Esc leaves Status focus so lazyzephyr hotkeys work again.",
    "The chip icon's color tracks live serial status — green is good.",
    "Status's Devices tab will eventually show parsed `device list` output from the Zephyr shell.",
    "Themes cycle with t — gruvbox, tailwind, catppuccin, tokyonight, solarized.",
];

pub fn render(frame: &mut Frame, area: Rect, app: &App) {
    let theme = app.theme();
    let border_color = if app.command_log_focused {
        theme.accent
    } else {
        theme.border
    };

    let chrome = if app.command_log_focused { theme.accent } else { theme.label };
    let title = Line::from(vec![
        Span::raw("[").fg(chrome),
        Span::raw("@").fg(chrome).bold(),
        Span::raw("]─").fg(chrome),
        Span::raw("Command log").fg(chrome),
    ]);
    let block = Block::bordered()
        .border_style(Style::new().fg(border_color))
        .title(title);
    let inner = block.inner(area);
    frame.render_widget(block, area);
    if inner.height == 0 {
        return;
    }

    let tip = TIPS[(app.frame_tick as usize / 600) % TIPS.len()];

    let mut lines: Vec<Line<'static>> = vec![
        Line::from(vec![
            Span::raw("Random tip: ").fg(theme.warning).bold(),
            Span::raw(tip).fg(theme.tiers[0]),
        ]),
    ];

    if !app.command_log_entries.is_empty() {
        lines.push(Line::from(""));
        for entry in &app.command_log_entries {
            lines.push(Line::from(Span::raw(entry.action.clone()).fg(theme.warning).bold()));
            lines.push(Line::from(vec![
                Span::raw("  ").fg(theme.label),
                Span::raw(entry.command.clone()).fg(theme.tiers[0]),
            ]));
        }
    }

    frame.render_widget(Paragraph::new(lines).wrap(Wrap { trim: false }), inner);
}
