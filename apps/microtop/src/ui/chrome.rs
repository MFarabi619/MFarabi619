use crate::app::App;
use ratatui::{
    Frame,
    layout::{Alignment, Constraint, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph, Widget},
};

pub fn render_navbar(frame: &mut Frame, app: &App, area: Rect) {
    let navbar_block = Block::default()
        .borders(Borders::BOTTOM)
        .border_style(Color::DarkGray);
    let navbar_inner_area = navbar_block.inner(area);
    navbar_block.render(area, frame.buffer_mut());

    let navbar_layout = Layout::horizontal([
        Constraint::Percentage(28),
        Constraint::Percentage(44),
        Constraint::Percentage(28),
    ])
    .split(navbar_inner_area);

    Paragraph::new(Line::from(vec![
        Span::styled(" 🪶 ", Style::default().fg(Color::Yellow)),
        Span::styled(
            "Apidae Systems",
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        ),
    ]))
    .render(navbar_layout[0], frame.buffer_mut());

    let search_hint_block = Block::bordered()
        .border_style(Color::DarkGray)
        .title(Line::from(vec![
            Span::styled(" Search... ", Style::default().fg(Color::DarkGray)),
            Span::styled("Ctrl+K ", Style::default().fg(Color::DarkGray)),
        ]));
    search_hint_block.render(navbar_layout[1], frame.buffer_mut());

    Paragraph::new(Line::from(vec![
        Span::styled(" API: ", Style::default().fg(Color::DarkGray)),
        Span::styled(
            app.api_base_url.as_str(),
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        ),
        Span::styled("  [i] edit", Style::default().fg(Color::DarkGray)),
    ]))
    .alignment(Alignment::Right)
    .render(navbar_layout[2], frame.buffer_mut());
}
