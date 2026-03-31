#[cfg(target_arch = "wasm32")]
use crate::app::FileSystemEntry;
use crate::{
    app::{App, FileSystemLoadState, FocusArea, MeasurementTab, NetworkScanLoadState},
    selectors,
};
#[cfg(target_arch = "wasm32")]
use ratatui::widgets::{List, ListItem};
use ratatui::{
    Frame,
    layout::{Alignment, Constraint, Layout, Rect},
    style::{Color, Modifier, Style, Stylize},
    symbols::border,
    text::{Line, Span},
    widgets::{
        Block, BorderType, Borders, Cell, Gauge, Paragraph, Row, Scrollbar, ScrollbarOrientation,
        ScrollbarState, Table, Tabs, Widget,
    },
};

#[cfg(not(target_arch = "wasm32"))]
use throbber_widgets_tui::{Throbber, WhichUse};
#[cfg(not(target_arch = "wasm32"))]
use tui_tree_widget::{Tree, TreeItem};

fn panel_border_color(is_focused: bool) -> Color {
    if is_focused {
        Color::Yellow
    } else {
        Color::DarkGray
    }
}

fn panel_hint_line(hints: &[(&str, &str)]) -> Line<'static> {
    let mut spans = Vec::new();
    for (label, shortcut) in hints {
        spans.push(Span::styled(
            format!(" {label} "),
            Style::default().fg(Color::DarkGray),
        ));
        spans.push(Span::styled(
            format!("<{shortcut}>"),
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        ));
    }
    Line::from(spans)
}

fn panel_table_block(title: &'static str) -> Block<'static> {
    Block::default()
        .title(format!(" {title} "))
        .borders(Borders::ALL)
        .border_style(Color::DarkGray)
}

pub fn render_measurement_panel(frame: &mut Frame, app: &App, area: Rect) {
    let measurement_block = Block::bordered()
        .border_set(border::THICK)
        .border_style(panel_border_color(
            app.focus_area == FocusArea::Measurements,
        ))
        .border_type(BorderType::Double)
        .title(" ⚡ Measurements ".yellow().bold())
        .title_bottom(panel_hint_line(&[
            ("Focus", "Tab"),
            ("Prev", "Shift+Tab"),
            ("Tabs", "h/l"),
            ("Palette", "?"),
            ("URL", "i"),
            ("Quit", "q"),
        ]));

    let measurement_inner_area = measurement_block.inner(area);
    measurement_block.render(area, frame.buffer_mut());

    let measurement_layout = Layout::vertical([
        Constraint::Length(3),
        Constraint::Length(2),
        Constraint::Min(8),
    ])
    .split(measurement_inner_area);

    let measurement_tabs = Tabs::new(vec!["Voltage", "Current"])
        .select(app.measurement_tab.index())
        .style(Style::default().fg(Color::DarkGray))
        .highlight_style(
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        )
        .divider(" ");
    frame.render_widget(measurement_tabs, measurement_layout[0]);

    let heading_layout =
        Layout::horizontal([Constraint::Percentage(70), Constraint::Percentage(30)])
            .split(measurement_layout[1]);

    let measurement_title = match app.measurement_tab {
        MeasurementTab::Voltage => "Channels (V)",
        MeasurementTab::Current => "Monitor",
    };

    Paragraph::new(Line::from(Span::styled(
        format!(" {measurement_title}"),
        Style::default()
            .fg(Color::Yellow)
            .add_modifier(Modifier::BOLD),
    )))
    .render(heading_layout[0], frame.buffer_mut());

    Block::bordered()
        .border_style(Color::DarkGray)
        .title(Line::from(vec![
            Span::styled(" ⚗ Sample ", Style::default().fg(Color::Yellow)),
            Span::styled("Ctrl+Enter", Style::default().fg(Color::DarkGray)),
        ]))
        .render(heading_layout[1], frame.buffer_mut());

    render_measurement_table(frame, app.measurement_tab, measurement_layout[2]);
}

fn render_measurement_table(frame: &mut Frame, measurement_tab: MeasurementTab, area: Rect) {
    let (header_cells, table_constraints) = match measurement_tab {
        MeasurementTab::Voltage => (
            vec!["#", "0", "1", "2", "3", "TIME"],
            vec![
                Constraint::Length(3),
                Constraint::Length(10),
                Constraint::Length(10),
                Constraint::Length(10),
                Constraint::Length(10),
                Constraint::Length(12),
            ],
        ),
        MeasurementTab::Current => (
            vec![
                "#",
                "CURRENT (mA)",
                "BUS (V)",
                "SHUNT (mV)",
                "POWER (mW)",
                "TEMP (C)",
                "TIME",
            ],
            vec![
                Constraint::Length(3),
                Constraint::Length(12),
                Constraint::Length(10),
                Constraint::Length(12),
                Constraint::Length(11),
                Constraint::Length(9),
                Constraint::Length(12),
            ],
        ),
    };

    let measurement_table = Table::new(std::iter::empty::<Row<'_>>(), table_constraints)
        .header(
            Row::new(header_cells).style(
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD),
            ),
        )
        .column_spacing(1)
        .block(panel_table_block("Readings"));
    frame.render_widget(measurement_table, area);

    let centered_hint_area = Layout::vertical([
        Constraint::Fill(1),
        Constraint::Length(3),
        Constraint::Fill(1),
    ])
    .split(area)[1];

    Paragraph::new(vec![
        Line::from(Span::styled(
            " ⚡ No readings yet",
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        )),
        Line::from(Span::styled(
            " Press Ctrl+Enter to capture data.",
            Style::default().fg(Color::DarkGray),
        )),
    ])
    .alignment(Alignment::Center)
    .render(centered_hint_area, frame.buffer_mut());
}

pub fn render_network_panel(frame: &mut Frame, app: &mut App, area: Rect) {
    let network_panel_block = Block::bordered()
        .border_set(border::THICK)
        .border_style(panel_border_color(app.focus_area == FocusArea::Network))
        .border_type(BorderType::Double)
        .title(" 📡 Network ".yellow().bold())
        .title_bottom(panel_hint_line(&[("Scan", "s"), ("Move", "j/k")]));

    let network_inner_area = network_panel_block.inner(area);
    network_panel_block.render(area, frame.buffer_mut());

    let network_layout = Layout::vertical([
        Constraint::Length(3),
        Constraint::Length(1),
        Constraint::Min(4),
    ])
    .split(network_inner_area);

    let access_point_ip = selectors::access_point_ip_text(app);
    let scan_status_text = selectors::network_scan_status_text(app);

    Paragraph::new(vec![
        Line::from(vec![
            Span::styled(" AP IP: ", Style::default().fg(Color::DarkGray)),
            Span::styled(access_point_ip, Style::default().fg(Color::Yellow)),
        ]),
        Line::from(vec![
            Span::styled(" Status: ", Style::default().fg(Color::DarkGray)),
            Span::styled(scan_status_text, Style::default().fg(Color::Yellow)),
        ]),
    ])
    .render(network_layout[0], frame.buffer_mut());

    if matches!(app.network_scan_load_state, NetworkScanLoadState::Loading) {
        #[cfg(not(target_arch = "wasm32"))]
        {
            let loading_throbber = Throbber::default()
                .label(" scanning...")
                .style(Style::default().fg(Color::DarkGray))
                .throbber_style(Style::default().fg(Color::Yellow))
                .use_type(WhichUse::Spin);
            frame.render_stateful_widget(
                loading_throbber,
                network_layout[1],
                &mut app.network_throbber_state,
            );
        }

        #[cfg(target_arch = "wasm32")]
        {
            Paragraph::new(" Scanning...").render(network_layout[1], frame.buffer_mut());
        }
    }

    if let NetworkScanLoadState::Error(error_message) = &app.network_scan_load_state {
        Paragraph::new(Line::from(vec![Span::styled(
            format!(" {error_message}"),
            Style::default().fg(Color::LightRed),
        )]))
        .render(network_layout[1], frame.buffer_mut());
    }

    let (connected_ssid, connected_station_ip) = selectors::connected_network_identity(app);

    let network_rows = app.wireless_networks.iter().map(|wireless_network_entry| {
        let mut ssid_display_value = if wireless_network_entry.ssid.is_empty() {
            "(hidden)".to_owned()
        } else {
            wireless_network_entry.ssid.clone()
        };
        if connected_ssid
            .as_ref()
            .is_some_and(|connected_ssid| connected_ssid == &wireless_network_entry.ssid)
        {
            ssid_display_value = format!("{} ({connected_station_ip})", ssid_display_value);
        }

        Row::new(vec![
            Cell::from(ssid_display_value),
            Cell::from(wireless_network_entry.rssi.to_string()),
            Cell::from(wireless_network_entry.channel.to_string()),
            Cell::from(wireless_network_entry.encryption.clone()),
        ])
    });

    let network_table = Table::new(
        network_rows,
        [
            Constraint::Percentage(44),
            Constraint::Length(8),
            Constraint::Length(9),
            Constraint::Percentage(35),
        ],
    )
    .header(
        Row::new(vec!["SSID", "RSSI", "CHANNEL", "SECURITY"]).style(
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        ),
    )
    .row_highlight_style(
        Style::default()
            .fg(Color::LightGreen)
            .bg(Color::Rgb(18, 36, 18))
            .add_modifier(Modifier::BOLD),
    )
    .highlight_symbol("▶ ")
    .column_spacing(1)
    .block(panel_table_block("Networks"));

    if app.wireless_networks.is_empty() {
        app.network_table_state.select(None);
        Paragraph::new(Line::from(vec![Span::styled(
            " No networks yet. Press s to scan.",
            Style::default().fg(Color::DarkGray),
        )]))
        .block(panel_table_block("Networks"))
        .render(network_layout[2], frame.buffer_mut());
        return;
    }

    if app.network_table_state.selected().is_none() {
        app.network_table_state.select(Some(0));
    }
    frame.render_stateful_widget(
        network_table,
        network_layout[2],
        &mut app.network_table_state,
    );

    let selected_network_index = app.network_table_state.selected().unwrap_or(0);
    let mut scrollbar_state = ScrollbarState::default()
        .content_length(app.wireless_networks.len().max(1))
        .position(selected_network_index);
    let scrollbar = Scrollbar::new(ScrollbarOrientation::VerticalRight)
        .thumb_style(Style::default().fg(Color::Yellow));
    frame.render_stateful_widget(scrollbar, network_layout[2], &mut scrollbar_state);
}

pub fn render_filesystem_panel(frame: &mut Frame, app: &mut App, area: Rect) {
    let filesystem_panel_block = Block::bordered()
        .border_set(border::THICK)
        .border_style(panel_border_color(app.focus_area == FocusArea::FileSystem))
        .border_type(BorderType::Double)
        .title(" 📚 Filesystem ".yellow().bold())
        .title_bottom(panel_hint_line(&[("Refresh", "r"), ("Move", "j/k")]));
    let filesystem_inner_area = filesystem_panel_block.inner(area);
    filesystem_panel_block.render(area, frame.buffer_mut());

    let filesystem_layout = Layout::vertical([
        Constraint::Length(4),
        Constraint::Length(4),
        Constraint::Min(5),
    ])
    .split(filesystem_inner_area);

    let sd_used_bytes = app.sd_used_bytes();
    let littlefs_used_bytes = app.littlefs_used_bytes();

    Gauge::default()
        .block(panel_table_block("SD Usage"))
        .gauge_style(Style::default().fg(Color::Yellow))
        .label(format!(
            "{} / {}",
            App::format_file_size(sd_used_bytes),
            App::format_file_size(app.sd_total_bytes)
        ))
        .ratio(App::storage_ratio(sd_used_bytes, app.sd_total_bytes))
        .render(filesystem_layout[0], frame.buffer_mut());

    Gauge::default()
        .block(panel_table_block("LittleFS Usage"))
        .gauge_style(Style::default().fg(Color::Yellow))
        .label(format!(
            "{} / {}",
            App::format_file_size(littlefs_used_bytes),
            App::format_file_size(app.littlefs_total_bytes)
        ))
        .ratio(App::storage_ratio(
            littlefs_used_bytes,
            app.littlefs_total_bytes,
        ))
        .render(filesystem_layout[1], frame.buffer_mut());

    if matches!(app.file_system_load_state, FileSystemLoadState::Loading) {
        #[cfg(not(target_arch = "wasm32"))]
        {
            let loading_throbber = Throbber::default()
                .label(" loading filesystem...")
                .style(Style::default().fg(Color::DarkGray))
                .throbber_style(Style::default().fg(Color::Yellow))
                .use_type(WhichUse::Spin);
            frame.render_stateful_widget(
                loading_throbber,
                filesystem_layout[2],
                &mut app.file_system_throbber_state,
            );
            return;
        }

        #[cfg(target_arch = "wasm32")]
        {
            Paragraph::new(" Loading filesystem...")
                .render(filesystem_layout[2], frame.buffer_mut());
            return;
        }
    }

    if let FileSystemLoadState::Error(error_message) = &app.file_system_load_state {
        Paragraph::new(Line::from(vec![Span::styled(
            format!(" Error: {error_message}"),
            Style::default().fg(Color::LightRed),
        )]))
        .block(panel_table_block("Files"))
        .render(filesystem_layout[2], frame.buffer_mut());
        return;
    }

    #[cfg(not(target_arch = "wasm32"))]
    {
        let file_system_tree_items = build_file_system_tree_items(app);
        if let Ok(file_system_tree) = Tree::new(&file_system_tree_items) {
            let file_system_tree_widget = file_system_tree
                .block(panel_table_block("Files"))
                .highlight_style(
                    Style::default()
                        .fg(Color::LightGreen)
                        .bg(Color::Rgb(22, 22, 22))
                        .add_modifier(Modifier::BOLD),
                )
                .highlight_symbol("▶ ")
                .node_closed_symbol("▸ ")
                .node_open_symbol("▾ ");

            frame.render_stateful_widget(
                file_system_tree_widget,
                filesystem_layout[2],
                &mut app.file_system_tree_state,
            );
            return;
        }
    }

    #[cfg(target_arch = "wasm32")]
    {
        render_filesystem_list_fallback(frame, app, filesystem_layout[2]);
    }
}

#[cfg(not(target_arch = "wasm32"))]
fn build_file_system_tree_items(app: &App) -> Vec<TreeItem<'static, String>> {
    let (sd_entries, littlefs_entries) = app.split_file_system_entries();

    let sd_children: Vec<TreeItem<'static, String>> = if sd_entries.is_empty() {
        vec![TreeItem::new_leaf("sd-empty".to_owned(), "No files found.")]
    } else {
        sd_entries
            .iter()
            .map(|file_system_entry| {
                TreeItem::new_leaf(
                    format!("sd:{}", file_system_entry.name),
                    format!(
                        "📄 {} ({})",
                        App::display_file_name(file_system_entry, "sd/"),
                        App::format_file_size(file_system_entry.size)
                    ),
                )
            })
            .collect()
    };

    let littlefs_children: Vec<TreeItem<'static, String>> = if littlefs_entries.is_empty() {
        vec![TreeItem::new_leaf(
            "littlefs-empty".to_owned(),
            "No files found.",
        )]
    } else {
        littlefs_entries
            .iter()
            .map(|file_system_entry| {
                TreeItem::new_leaf(
                    format!("littlefs:{}", file_system_entry.name),
                    format!(
                        "📄 {} ({})",
                        App::display_file_name(file_system_entry, "littlefs/"),
                        App::format_file_size(file_system_entry.size)
                    ),
                )
            })
            .collect()
    };

    let sd_root = TreeItem::new("sd-root".to_owned(), "💾 SD Card", sd_children)
        .unwrap_or_else(|_| TreeItem::new_leaf("sd-root".to_owned(), "💾 SD Card"));
    let littlefs_root = TreeItem::new("littlefs-root".to_owned(), "🐁 LittleFS", littlefs_children)
        .unwrap_or_else(|_| TreeItem::new_leaf("littlefs-root".to_owned(), "🐁 LittleFS"));
    vec![sd_root, littlefs_root]
}

#[cfg(target_arch = "wasm32")]
fn render_filesystem_list_fallback(frame: &mut Frame, app: &mut App, area: Rect) {
    let (sd_entries, littlefs_entries) = app.split_file_system_entries();
    let mut list_items = file_system_section_items(
        "💾 SD Card",
        &sd_entries,
        "sd/",
        &app.file_system_load_state,
    );
    list_items.push(ListItem::new(Line::from("")));
    list_items.extend(file_system_section_items(
        "🐁 LittleFS",
        &littlefs_entries,
        "littlefs/",
        &app.file_system_load_state,
    ));

    if app.file_system_list_state.selected().is_none() && !list_items.is_empty() {
        app.file_system_list_state.select(Some(0));
    }

    let file_list = List::new(list_items)
        .highlight_style(
            Style::default()
                .fg(Color::LightGreen)
                .bg(Color::Rgb(22, 22, 22)),
        )
        .highlight_symbol("▶ ");
    frame.render_stateful_widget(file_list, area, &mut app.file_system_list_state);

    let selected_index = app.file_system_list_state.selected().unwrap_or(0);
    let mut scrollbar_state = ScrollbarState::default()
        .content_length(app.file_system_render_row_count().max(1))
        .position(selected_index);
    let scrollbar = Scrollbar::new(ScrollbarOrientation::VerticalRight)
        .thumb_style(Style::default().fg(Color::Yellow));
    frame.render_stateful_widget(scrollbar, area, &mut scrollbar_state);
}

#[cfg(target_arch = "wasm32")]
fn file_system_section_items(
    section_title: &str,
    file_system_entries: &[&FileSystemEntry],
    source_prefix: &str,
    file_system_load_state: &FileSystemLoadState,
) -> Vec<ListItem<'static>> {
    let mut section_items = vec![
        ListItem::new(Line::from(vec![Span::styled(
            section_title.to_owned(),
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        )])),
        ListItem::new(Line::from("")),
    ];

    match file_system_load_state {
        FileSystemLoadState::Idle => {
            section_items.push(ListItem::new(Line::from("Press r to load files")))
        }
        FileSystemLoadState::Loading => {
            section_items.push(ListItem::new(Line::from("Loading filesystem...")))
        }
        FileSystemLoadState::Error(error_message) => {
            section_items.push(ListItem::new(Line::from(vec![Span::styled(
                format!("Error: {error_message}"),
                Style::default().fg(Color::LightRed),
            )])))
        }
        FileSystemLoadState::Loaded => {
            if file_system_entries.is_empty() {
                section_items.push(ListItem::new(Line::from(vec![Span::styled(
                    "No files found.",
                    Style::default().fg(Color::DarkGray),
                )])));
            } else {
                for file_system_entry in file_system_entries {
                    section_items.push(ListItem::new(Line::from(vec![
                        Span::styled("📄 ", Style::default().fg(Color::LightYellow)),
                        Span::styled(
                            App::display_file_name(file_system_entry, source_prefix),
                            Style::default().fg(Color::Yellow),
                        ),
                        Span::raw("  "),
                        Span::styled(
                            App::format_file_size(file_system_entry.size),
                            Style::default().fg(Color::DarkGray),
                        ),
                    ])));
                }
            }
        }
    }

    section_items
}
