use ratatui::{
    Frame,
    layout::Rect,
    style::Style,
    widgets::Block,
};

use crate::tui::{render::overlay_detail_tabs, state::App};

pub fn render(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = *app.theme();
    let panel = app.current_panel();
    let focused = app.detail_focused;

    let tabs = panel.detail_tabs(app);
    let active = app.current_state().detail_tab.min(tabs.len().saturating_sub(1));

    let block = Block::bordered()
        .border_type(theme.border_type)
        .border_style(Style::new().fg(if focused { theme.accent } else { theme.border }));
    let inner = block.inner(area);
    frame.render_widget(block, area);
    overlay_detail_tabs(frame, area, &theme, &tabs, active, focused);
    if inner.height == 0 { return; }

    let label = tabs.get(active).copied().unwrap_or("Logs");
    panel.render_detail(frame, inner, app, label);
}
