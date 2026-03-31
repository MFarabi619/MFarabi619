use ratatui::layout::{Constraint, Layout, Rect};

pub struct DashboardLayoutAreas {
    pub navbar_area: Rect,
    pub measurements_panel_area: Rect,
    pub network_panel_area: Rect,
    pub filesystem_panel_area: Rect,
}

pub fn split_dashboard(frame_area: Rect) -> DashboardLayoutAreas {
    let root_layout = Layout::vertical([Constraint::Length(3), Constraint::Min(0)])
        .spacing(1)
        .split(frame_area);

    let content_layout = Layout::vertical([Constraint::Fill(11), Constraint::Fill(14)])
        .spacing(1)
        .split(root_layout[1]);

    let bottom_layout = Layout::horizontal([Constraint::Fill(17), Constraint::Fill(8)])
        .spacing(1)
        .split(content_layout[1]);

    DashboardLayoutAreas {
        navbar_area: root_layout[0],
        measurements_panel_area: content_layout[0],
        network_panel_area: bottom_layout[0],
        filesystem_panel_area: bottom_layout[1],
    }
}
