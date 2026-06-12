use alloc::{format, string::ToString, vec::Vec};

use ratatui::{
    Frame,
    layout::Rect,
    macros::{horizontal, line},
    style::{
        Stylize,
        palette::tailwind::{AMBER, ROSE},
    },
    text::{Line, Span},
    widgets::Paragraph,
};

use crate::{
    theme::Theme,
    tui::{input::InputMode, state::App},
};

pub fn render_footer(frame: &mut Frame, area: Rect, app: &App) {
    let theme = app.theme();
    let [hints_area, status_area] = horizontal![*=1, ==32].areas(area);
    frame.render_widget(Paragraph::new(build_hints(theme, app)), hints_area);
    frame.render_widget(Paragraph::new(build_status(theme)).right_aligned(), status_area);
}

fn build_hints(theme: &Theme, app: &App) -> Line<'static> {
    if app.mode == InputMode::Search {
        return build_search_bar(theme, app);
    }
    let mut spans: Vec<Span<'static>> = Vec::new();
    spans.push(" ".into());

    let panel_b = app.current_panel().bindings(app);
    let global_b = crate::tui::keybindings::global_bindings();
    let all = panel_b.iter().chain(global_b.iter()).filter(|b| b.display_on_screen);
    for (i, b) in all.enumerate() {
        if i > 0 {
            spans.push(" | ".fg(theme.border));
        }
        spans.push(format!("{}: ", b.label()).fg(theme.label));
        spans.push(b.display_key().to_string().fg(theme.options_text).bold());
    }
    Line::from(spans)
}

fn build_search_bar(theme: &Theme, app: &App) -> Line<'static> {
    let filter = app.current_state().list.filter.clone();
    line![
        " SEARCH ".fg(theme.selection_foreground).bg(theme.options_text).bold(),
        " /".fg(theme.label),
        filter.fg(theme.value).bold(),
        "▏".fg(theme.options_text).bold(),
        "   Enter ".fg(theme.label),
        "apply ".fg(theme.label),
        " Esc ".fg(theme.label),
        "clear".fg(theme.label),
    ]
}

fn build_status(theme: &Theme) -> Line<'static> {
    line![
        "Donate".fg(ROSE.c300).underlined(),
        " ",
        "Ask Question".fg(AMBER.c400).underlined(),
        " ",
        env!("CARGO_PKG_VERSION").fg(theme.foreground),
        " ",
    ]
}
