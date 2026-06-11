mod at_modal;
mod command_log;
mod detail;
mod events;
mod footer;
mod heap_pools;
mod help;
mod network;
pub mod status;
mod threads;
mod widgets;

pub use events::EventsPanel;
pub use heap_pools::HeapPoolsPanel;
pub use network::NetworkPanel;
pub use status::StatusPanel;
pub use threads::ThreadsPanel;

use alloc::vec::Vec;

use ratatui::{
    Frame,
    layout::{Constraint, Layout, Rect},
};

use crate::{
    app::App,
    panel::{Panel, PanelTag},
};

pub const PANELS: &[&dyn Panel] = &[
    &StatusPanel,
    &ThreadsPanel,
    &HeapPoolsPanel,
    &NetworkPanel,
    &EventsPanel,
];

pub fn render(frame: &mut Frame, app: &mut App) {
    let area = frame.area();
    let [body_area, footer_area] = Layout::vertical([
        Constraint::Min(0),
        Constraint::Length(1),
    ])
    .areas(area);

    render_body(frame, body_area, app);
    footer::render_footer(frame, footer_area, app);

    if app.help_open {
        help::render_help(frame, app);
    }
    if app.at_modal_open {
        at_modal::render(frame, app);
    }
}

fn render_body(frame: &mut Frame, area: Rect, app: &mut App) {
    let [left_rail, right_column] = Layout::horizontal([
        Constraint::Percentage(40),
        Constraint::Percentage(60),
    ])
    .areas(area);

    let log_height: u16 = if app.command_log_shown { 6 } else { 0 };
    let [detail_area, log_area] = Layout::vertical([
        Constraint::Min(0),
        Constraint::Length(log_height),
    ])
    .areas(right_column);

    let constraints: Vec<Constraint> = PANELS.iter().enumerate().map(|(i, panel)| {
        match panel.tag() {
            PanelTag::Status | PanelTag::Events => {
                if app.focused_index == i { Constraint::Fill(1) }
                else                      { Constraint::Length(3) }
            }
            _ => Constraint::Fill(1),
        }
    }).collect();

    let areas = Layout::vertical(constraints).split(left_rail);
    app.detail_rect = detail_area;
    for (i, panel) in PANELS.iter().enumerate() {
        app.panel_rects[i] = areas[i];
        let is_current = app.focused_index == i;
        let focused = is_current && !app.detail_focused;
        panel.render_list(frame, areas[i], app, focused);
    }
    detail::render(frame, detail_area, app);

    if app.command_log_shown {
        app.command_log_rect = log_area;
        command_log::render(frame, log_area, app);
    } else {
        app.command_log_rect = Rect::default();
    }
}
