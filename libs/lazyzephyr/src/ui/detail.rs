use ratatui::{
    Frame,
    layout::Rect,
    style::Style,
    widgets::Block,
};

use crate::{
    app::App,
    ui::widgets::tabs_title,
};

pub fn render(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = *app.theme();
    let panel = app.current_panel();
    let focused = app.detail_focused;

    let tabs = panel.detail_tabs(app);
    let active = app.current_state().detail_tab.min(tabs.len().saturating_sub(1));

    let title = tabs_title(&theme, &tabs, active, focused);
    let block = Block::bordered()
        .border_style(Style::new().fg(if focused { theme.accent } else { theme.border }))
        .title(title);
    let inner = block.inner(area);
    frame.render_widget(block, area);
    if inner.height == 0 { return; }

    let label = tabs.get(active).copied().unwrap_or("Logs");
    panel.render_detail(frame, inner, app, label);
}
