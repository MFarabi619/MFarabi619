use alloc::{format, string::ToString, vec, vec::Vec};

use ratatui::{
    Frame,
    layout::{Constraint, Layout, Rect},
    style::{
        Stylize,
        palette::tailwind::{AMBER, ROSE},
    },
    text::{Line, Span},
    widgets::Paragraph,
};

use crate::{
    app::App,
    input::InputMode,
    theme::Theme,
};

pub fn render_footer(frame: &mut Frame, area: Rect, app: &App) {
    let theme = app.theme();
    let [hints_area, status_area] = Layout::horizontal([
        Constraint::Fill(1),
        Constraint::Length(32),
    ])
    .areas(area);

    frame.render_widget(Paragraph::new(build_hints(theme, app)), hints_area);
    frame.render_widget(Paragraph::new(build_status(theme)).right_aligned(), status_area);
}

fn build_hints(theme: &Theme, app: &App) -> Line<'static> {
    if app.mode == InputMode::Search {
        return build_search_bar(theme, app);
    }
    let mut spans: Vec<Span<'static>> = Vec::new();
    spans.push(Span::raw(" "));

    let actions = app.current_panel().footer_actions(app);
    for (label, key) in &actions {
        push_action(&mut spans, theme, label, key);
        push_separator(&mut spans, theme);
    }
    push_action(&mut spans, theme, "Keybindings", "?");
    Line::from(spans)
}

fn build_search_bar(theme: &Theme, app: &App) -> Line<'static> {
    let filter = app.current_state().filter.clone();
    Line::from(vec![
        Span::raw(" SEARCH ").fg(theme.selection_foreground).bg(theme.accent).bold(),
        Span::raw(" /").fg(theme.label),
        Span::raw(filter).fg(theme.value).bold(),
        Span::raw("▏").fg(theme.accent).bold(),
        Span::raw("   Enter ").fg(theme.label),
        Span::raw("apply ").fg(theme.label),
        Span::raw(" Esc ").fg(theme.label),
        Span::raw("clear").fg(theme.label),
    ])
}

fn push_action(spans: &mut Vec<Span<'static>>, theme: &Theme, label: &str, key: &str) {
    spans.push(Span::raw(format!("{label}: ")).fg(theme.label));
    spans.push(Span::raw(key.to_string()).fg(theme.accent).bold());
}

fn push_separator(spans: &mut Vec<Span<'static>>, theme: &Theme) {
    spans.push(Span::raw(" | ").fg(theme.border));
}

fn build_status(theme: &Theme) -> Line<'static> {
    Line::from(vec![
        Span::raw("Donate").fg(ROSE.c300).underlined(),
        Span::raw(" "),
        Span::raw("Ask Question").fg(AMBER.c400).underlined(),
        Span::raw(" "),
        Span::raw(env!("CARGO_PKG_VERSION")).fg(theme.foreground),
        Span::raw(" "),
    ])
}
