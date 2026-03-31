mod chrome;
mod layout;
mod overlays;
mod panels;

use crate::app::App;
use ratatui::Frame;

pub fn render(frame: &mut Frame, app: &mut App) {
    let dashboard_layout_areas = layout::split_dashboard(frame.area());

    chrome::render_navbar(frame, app, dashboard_layout_areas.navbar_area);
    panels::render_measurement_panel(frame, app, dashboard_layout_areas.measurements_panel_area);

    app.dashboard_areas.measurements_area = dashboard_layout_areas.measurements_panel_area;
    app.dashboard_areas.network_area = dashboard_layout_areas.network_panel_area;
    app.dashboard_areas.filesystem_area = dashboard_layout_areas.filesystem_panel_area;

    panels::render_network_panel(frame, app, dashboard_layout_areas.network_panel_area);
    panels::render_filesystem_panel(frame, app, dashboard_layout_areas.filesystem_panel_area);

    if app.command_palette_open {
        overlays::render_command_palette(frame, app);
    }

    if app.api_base_url_editor_open {
        overlays::render_api_base_url_editor(frame, app);
    }
}
