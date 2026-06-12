use alloc::vec::Vec;

use ratatui::{
    Frame,
    layout::{Constraint, Layout, Rect},
};

use crate::tui::{
    command_log, help, main_panels, menu_panel, options_map,
    panel::{Panel, PanelTag},
    panes::{AnalyzePanel, KernelPanel, McumgrPanel, StatusPanel, WipPanel},
    state::App,
};

pub const PANELS: &[&dyn Panel] = &[
    &StatusPanel,
    &McumgrPanel,
    &KernelPanel,
    &AnalyzePanel,
    &WipPanel,
];

pub fn layout(frame: &mut Frame, app: &mut App) {
    let area = frame.area();
    let footer_height: u16 = if app.config.gui.show_bottom_line { 1 } else { 0 };
    let [body_area, footer_area] = Layout::vertical([
        Constraint::Fill(1),
        Constraint::Length(footer_height),
    ])
    .areas(area);

    render_body(frame, body_area, app);
    if footer_height > 0 {
        options_map::render_footer(frame, footer_area, app);
    }

    for overlay in app.popups.clone() {
        use crate::tui::{dialog, popup::Popup};
        match overlay {
            Popup::Help            => help::render_help(frame, app),
            Popup::Menu    { .. }  => menu_panel::render(frame, app),
            Popup::Confirm { .. } => dialog::render_confirm(frame, app),
            Popup::Alert   { .. } => dialog::render_alert(frame, app),
            Popup::Prompt  { .. } => dialog::render_prompt(frame, app),
            Popup::Toast   { .. } => dialog::render_toast(frame, app),
            Popup::Waiting { .. } => dialog::render_waiting(frame, app),
        }
    }
}

fn render_body(frame: &mut Frame, area: Rect, app: &mut App) {
    let left_pct  = (app.config.gui.side_panel_width.clamp(0.05, 0.95) * 100.0) as u16;
    let right_pct = 100u16.saturating_sub(left_pct);
    let [left_rail, right_column] = Layout::horizontal([
        Constraint::Percentage(left_pct),
        Constraint::Percentage(right_pct),
    ])
    .areas(area);

    let log_height: u16 = if app.command_log_shown { app.config.gui.command_log_size } else { 0 };
    let [detail_area, log_area] = Layout::vertical([
        Constraint::Fill(1),
        Constraint::Length(log_height),
    ])
    .areas(right_column);

    let constraints: Vec<Constraint> = PANELS.iter().enumerate().map(|(i, panel)| {
        match panel.tag() {
            PanelTag::Status | PanelTag::Wip => {
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
    main_panels::render(frame, detail_area, app);

    if app.command_log_shown {
        app.command_log_rect = log_area;
        command_log::render(frame, log_area, app);
    } else {
        app.command_log_rect = Rect::default();
    }
}
