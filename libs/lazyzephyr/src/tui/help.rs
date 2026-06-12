use alloc::{format, string::{String, ToString}, vec::Vec};

use ratatui::{
    Frame,
    layout::Constraint,
    macros::line,
    style::Stylize,
    text::Line,
    widgets::Paragraph,
};

use crate::tui::{
    keybindings::{Binding, global_bindings},
    layout::PANELS,
    popup_chrome::{chrome_title, render_chrome},
    state::App,
};

pub fn render_help(frame: &mut Frame, app: &App) {
    let theme = app.theme();
    let area = frame.area().centered(Constraint::Percentage(64), Constraint::Percentage(72));
    let inner = render_chrome(frame, area, theme, chrome_title(theme, " ? Help · keyboard shortcuts "));

    let panel_label = app.current_panel().label();
    let mut grouped: alloc::collections::BTreeMap<&'static str, Vec<Binding>> = alloc::collections::BTreeMap::new();
    for b in app.current_panel().bindings(app) {
        grouped.entry(if b.tag.is_empty() { panel_label } else { b.tag }).or_default().push(b);
    }
    for b in global_bindings() {
        grouped.entry(b.tag).or_default().push(b);
    }
    for (i, panel) in PANELS.iter().enumerate() {
        grouped.entry("navigation").or_default().insert(0, Binding::new(
            pane_key(i),
            pane_focus_desc(panel.label()),
        ).tag("navigation"));
    }

    let mut lines: Vec<Line<'static>> = Vec::new();
    for (heading, bindings) in &grouped {
        if !lines.is_empty() { lines.push(Line::from("")); }
        lines.push(line![format!(" {} ", heading.to_uppercase()).fg(theme.options_text).bold()]);
        for b in bindings {
            let keys = format_keys(b);
            lines.push(line![
                format!(" {keys:<22} ").fg(theme.accent).bold(),
                b.description.to_string().fg(theme.label),
            ]);
        }
    }

    frame.render_widget(Paragraph::new(lines), inner);
}

fn format_keys(b: &Binding) -> String {
    let mut out = String::new();
    for (i, k) in b.keys.iter().enumerate() {
        if i > 0 { out.push_str("  "); }
        out.push_str(k);
    }
    out
}

fn pane_key(i: usize) -> &'static [&'static str] {
    match i {
        0 => &["1"],
        1 => &["2"],
        2 => &["3"],
        3 => &["4"],
        _ => &["5"],
    }
}

fn pane_focus_desc(label: &'static str) -> &'static str {
    match label {
        "Status"     => "focus Status pane",
        "Kernel"     => "focus Kernel pane",
        "Heap pools" => "focus Heap pools pane",
        "Network"    => "focus Network pane",
        "Analyze"    => "focus Analyze pane",
        _            => "focus pane",
    }
}
