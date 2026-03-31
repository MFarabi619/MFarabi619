use crate::app::{App, COMMAND_PALETTE_ITEMS, CommandPaletteGroup};
use ratatui::{
    Frame,
    layout::{Constraint, Layout},
    style::{Color, Modifier, Style, Stylize},
    text::{Line, Span},
    widgets::{Block, BorderType, Borders, Clear, List, ListItem, Paragraph, Widget},
};

pub fn render_command_palette(frame: &mut Frame, app: &App) {
    let popup_area = Layout::vertical([
        Constraint::Percentage(22),
        Constraint::Length(16),
        Constraint::Fill(1),
    ])
    .split(frame.area())[1];
    let popup_area = Layout::horizontal([
        Constraint::Percentage(24),
        Constraint::Length(66),
        Constraint::Fill(1),
    ])
    .split(popup_area)[1];

    Clear.render(popup_area, frame.buffer_mut());

    let popup_block = Block::bordered()
        .border_type(BorderType::Rounded)
        .border_style(Color::DarkGray)
        .title(" Command Palette ".yellow());
    let popup_inner_area = popup_block.inner(popup_area);
    popup_block.render(popup_area, frame.buffer_mut());

    let popup_layout =
        Layout::vertical([Constraint::Length(2), Constraint::Min(1)]).split(popup_inner_area);

    let input_line = Line::from(vec![
        Span::styled(" 🔍 ", Style::default().fg(Color::DarkGray)),
        Span::styled(
            if app.command_palette_query.is_empty() {
                "Type a command or search..."
            } else {
                app.command_palette_query.as_str()
            },
            if app.command_palette_query.is_empty() {
                Style::default().fg(Color::DarkGray)
            } else {
                Style::default().fg(Color::Yellow)
            },
        ),
    ]);
    Paragraph::new(input_line).render(popup_layout[0], frame.buffer_mut());

    let filtered_item_indices = app.filtered_command_item_indices();
    let selected_index = app.command_palette_selected_index();
    let mut visible_item_index = 0usize;
    let mut active_group: Option<CommandPaletteGroup> = None;
    let mut command_items = Vec::new();

    for item_index in filtered_item_indices {
        let command_item = &COMMAND_PALETTE_ITEMS[item_index];

        if active_group != Some(command_item.group) {
            active_group = Some(command_item.group);
            let heading = match command_item.group {
                CommandPaletteGroup::Actions => "Actions",
                CommandPaletteGroup::Navigate => "Navigate",
            };
            command_items.push(ListItem::new(Line::from(vec![Span::styled(
                format!(" {heading}"),
                Style::default()
                    .fg(Color::DarkGray)
                    .add_modifier(Modifier::BOLD),
            )])));
        }

        let command_item_style = if visible_item_index == selected_index {
            Style::default()
                .fg(Color::Yellow)
                .bg(Color::Rgb(50, 34, 12))
                .add_modifier(Modifier::BOLD)
        } else {
            Style::default().fg(Color::Gray)
        };

        command_items.push(ListItem::new(Line::from(vec![
            Span::styled(format!(" {} ", command_item.icon), command_item_style),
            Span::styled(command_item.label, command_item_style),
            Span::styled(" ", command_item_style),
            Span::styled(command_item.shortcut, Style::default().fg(Color::DarkGray)),
        ])));

        visible_item_index += 1;
    }

    if command_items.is_empty() {
        command_items.push(ListItem::new(Line::from(vec![Span::styled(
            " No results found.",
            Style::default().fg(Color::DarkGray),
        )])));
    }

    List::new(command_items)
        .block(Block::default().borders(Borders::TOP))
        .render(popup_layout[1], frame.buffer_mut());
}

pub fn render_api_base_url_editor(frame: &mut Frame, app: &App) {
    let popup_area = Layout::vertical([
        Constraint::Percentage(28),
        Constraint::Length(7),
        Constraint::Fill(1),
    ])
    .split(frame.area())[1];
    let popup_area = Layout::horizontal([
        Constraint::Percentage(22),
        Constraint::Length(72),
        Constraint::Fill(1),
    ])
    .split(popup_area)[1];

    Clear.render(popup_area, frame.buffer_mut());

    let popup_block = Block::bordered()
        .border_type(BorderType::Rounded)
        .border_style(Color::Yellow)
        .title(" Device API URL ".yellow().bold());
    let popup_inner_area = popup_block.inner(popup_area);
    popup_block.render(popup_area, frame.buffer_mut());

    let lines = vec![
        Line::from(vec![
            Span::styled(" URL: ", Style::default().fg(Color::DarkGray)),
            Span::styled(
                app.api_base_url_editor_buffer.as_str(),
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD),
            ),
        ]),
        Line::from(vec![
            Span::styled(" Enter ", Style::default().fg(Color::DarkGray)),
            Span::styled("apply", Style::default().fg(Color::Yellow)),
            Span::styled("  Esc ", Style::default().fg(Color::DarkGray)),
            Span::styled("cancel", Style::default().fg(Color::Yellow)),
        ]),
    ];

    Paragraph::new(lines).render(popup_inner_area, frame.buffer_mut());
}
