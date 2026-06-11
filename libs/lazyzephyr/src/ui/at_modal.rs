use alloc::{format, string::ToString, vec, vec::Vec};

use ratatui::{
    Frame,
    layout::{Constraint, Layout, Rect},
    style::{Style, Stylize},
    text::{Line, Span},
    widgets::{Block, Clear, Paragraph},
};

use crate::app::{App, AT_MODAL_OPTIONS};

pub fn render(frame: &mut Frame, app: &App) {
    let theme = app.theme();
    let width  = 52u16;
    let height = (AT_MODAL_OPTIONS.len() as u16) + 3;
    let area = centered(frame.area(), width, height);

    frame.render_widget(Clear, area);
    let block = Block::bordered()
        .border_style(Style::new().fg(theme.accent))
        .title(Span::raw(" Command log ").fg(theme.success).bold());
    let inner = block.inner(area);
    frame.render_widget(block, area);

    let [list_area, footer_area] = Layout::vertical([
        Constraint::Min(0),
        Constraint::Length(1),
    ])
    .areas(inner);

    let lines: Vec<Line<'static>> = AT_MODAL_OPTIONS.iter().enumerate().map(|(i, option)| {
        let selected = i == app.at_modal_selection;
        let row_style = if selected {
            Style::new().bg(theme.selection_background).fg(theme.selection_foreground).bold()
        } else {
            Style::new().fg(theme.value)
        };
        let key_text = option.key.map(|c| format!(" {c} ")).unwrap_or_else(|| "   ".into());
        Line::from(vec![
            Span::styled(key_text, Style::new().fg(theme.success).bold()),
            Span::styled(option.label.to_string(), row_style),
        ])
    }).collect();
    frame.render_widget(Paragraph::new(lines), list_area);

    let footer = Line::from(Span::raw(format!("{} of {} ", app.at_modal_selection + 1, AT_MODAL_OPTIONS.len()))
        .fg(theme.label));
    frame.render_widget(Paragraph::new(footer).right_aligned(), footer_area);
}

fn centered(screen: Rect, width: u16, height: u16) -> Rect {
    let w = width.min(screen.width.saturating_sub(2));
    let h = height.min(screen.height.saturating_sub(2));
    Rect {
        x:      screen.x + (screen.width.saturating_sub(w))  / 2,
        y:      screen.y + (screen.height.saturating_sub(h)) / 2,
        width:  w,
        height: h,
    }
}

