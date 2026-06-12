use alloc::{format, string::ToString, vec::Vec};

use ratatui::{
    Frame,
    layout::Constraint,
    macros::{line, vertical},
    style::{Style, Stylize},
    text::{Line, Span},
    widgets::Paragraph,
};

use crate::tui::{
    popup::Popup,
    popup_chrome::render_chrome,
    state::{App, MENU_OPTIONS},
};

pub fn render(frame: &mut Frame, app: &App) {
    let theme = app.theme();
    let selection = match app.popups.iter().rev().find(|o| matches!(o, Popup::Menu { .. })) {
        Some(Popup::Menu { selection }) => *selection,
        _ => return,
    };
    let width  = 52u16;
    let height = (MENU_OPTIONS.len() as u16) + 3;
    let area = frame.area().centered(Constraint::Length(width), Constraint::Length(height));
    let inner = render_chrome(frame, area, theme, " Command log ".fg(theme.success).bold().into());

    let [list_area, footer_area] = vertical![*=0, ==1].areas(inner);

    let lines: Vec<Line<'static>> = MENU_OPTIONS.iter().enumerate().map(|(i, option)| {
        let selected = i == selection;
        let row_style = if selected {
            Style::new().bg(theme.selection_background).fg(theme.selection_foreground).bold()
        } else {
            Style::new().fg(theme.value)
        };
        let key_text = option.key.map(|c| format!(" {c} ")).unwrap_or_else(|| "   ".into());
        line![
            key_text.fg(theme.success).bold(),
            Span::styled(option.label.to_string(), row_style),
        ]
    }).collect();
    frame.render_widget(Paragraph::new(lines), list_area);

    let footer = Line::from(format!("{} of {} ", selection + 1, MENU_OPTIONS.len()).fg(theme.label));
    frame.render_widget(Paragraph::new(footer).right_aligned(), footer_area);
}
