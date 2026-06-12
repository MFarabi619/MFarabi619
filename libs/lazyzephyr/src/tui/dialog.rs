use alloc::string::ToString;

use ratatui::{
    Frame,
    layout::{Constraint, Position},
    macros::{line, vertical},
    style::Stylize,
    text::Line,
    widgets::{Paragraph, Wrap},
};

use crate::tui::{
    popup::{Popup, ToastKind},
    popup_chrome::{chrome_title, render_chrome},
    state::App,
};

pub fn render_confirm(frame: &mut Frame, app: &App) {
    let Some((title, message)) = app.popups.iter().rev().find_map(|p| match p {
        Popup::Confirm { title, message, .. } => Some((*title, message.clone())),
        _ => None,
    }) else { return };
    let theme = app.theme();
    let width = 60u16.max(title.len() as u16 + 6).min(frame.area().width.saturating_sub(4));
    let lines = wrap_lines(&message, (width as usize).saturating_sub(4));
    let height = (lines.len() as u16) + 4;
    let area = frame.area().centered(Constraint::Length(width), Constraint::Length(height));
    let inner = render_chrome(frame, area, theme, chrome_title(theme, title));
    let [body, footer] = vertical![*=1, ==1].areas(inner);
    let body_lines: alloc::vec::Vec<Line<'static>> = lines.into_iter()
        .map(|l| Line::from(l.fg(theme.foreground)))
        .collect();
    frame.render_widget(Paragraph::new(body_lines).wrap(Wrap { trim: false }), body);
    frame.render_widget(
        Paragraph::new(line![
            " ".fg(theme.label),
            "Enter".fg(theme.accent).bold(), " confirm  ".fg(theme.label),
            "Esc".fg(theme.accent).bold(),   " cancel ".fg(theme.label),
        ]).right_aligned(),
        footer,
    );
}

pub fn render_alert(frame: &mut Frame, app: &App) {
    let Some((title, message)) = app.popups.iter().rev().find_map(|p| match p {
        Popup::Alert { title, message } => Some((*title, message.clone())),
        _ => None,
    }) else { return };
    let theme = app.theme();
    let width = 60u16.max(title.len() as u16 + 6).min(frame.area().width.saturating_sub(4));
    let lines = wrap_lines(&message, (width as usize).saturating_sub(4));
    let height = (lines.len() as u16) + 4;
    let area = frame.area().centered(Constraint::Length(width), Constraint::Length(height));
    let inner = render_chrome(frame, area, theme, chrome_title(theme, title));
    let [body, footer] = vertical![*=1, ==1].areas(inner);
    let body_lines: alloc::vec::Vec<Line<'static>> = lines.into_iter()
        .map(|l| Line::from(l.fg(theme.foreground)))
        .collect();
    frame.render_widget(Paragraph::new(body_lines).wrap(Wrap { trim: false }), body);
    frame.render_widget(
        Paragraph::new(line![
            " ".fg(theme.label),
            "Enter/Esc".fg(theme.accent).bold(), " dismiss ".fg(theme.label),
        ]).right_aligned(),
        footer,
    );
}

pub fn render_prompt(frame: &mut Frame, app: &App) {
    let Some((title, value, cursor)) = app.popups.iter().rev().find_map(|p| match p {
        Popup::Prompt { title, value, cursor, .. } => Some((*title, value.clone(), *cursor)),
        _ => None,
    }) else { return };
    let theme = app.theme();
    let width = 70u16.min(frame.area().width.saturating_sub(4));
    let area = frame.area().centered(Constraint::Length(width), Constraint::Length(5));
    let inner = render_chrome(frame, area, theme, chrome_title(theme, title));
    let [input_area, footer] = vertical![==1, *=1].areas(inner);
    let display = if value.is_empty() {
        line!["  ".fg(theme.label)]
    } else {
        line![" ".fg(theme.foreground), value.clone().fg(theme.value)]
    };
    frame.render_widget(Paragraph::new(display), input_area);
    frame.set_cursor_position(Position::new(input_area.x + 1 + cursor as u16, input_area.y));
    frame.render_widget(
        Paragraph::new(line![
            " ".fg(theme.label),
            "Enter".fg(theme.accent).bold(), " submit  ".fg(theme.label),
            "Esc".fg(theme.accent).bold(),   " cancel ".fg(theme.label),
        ]).right_aligned(),
        footer,
    );
}

pub fn render_waiting(frame: &mut Frame, app: &App) {
    let Some(message) = app.popups.iter().rev().find_map(|p| match p {
        Popup::Waiting { message, .. } => Some(message.clone()),
        _ => None,
    }) else { return };
    let theme = app.theme();
    let spinner = spinner_char(app.frame_tick);
    let width = (message.len() as u16 + 8).min(frame.area().width.saturating_sub(4));
    let area = frame.area().centered(Constraint::Length(width), Constraint::Length(3));
    let inner = render_chrome(frame, area, theme, chrome_title(theme, " "));
    let body = line![
        " ".fg(theme.label),
        spinner.fg(theme.warning).bold(),
        "  ".fg(theme.label),
        message.fg(theme.foreground).bold(),
    ];
    frame.render_widget(Paragraph::new(body), inner);
}

fn spinner_char(frame_tick: u32) -> &'static str {
    use throbber_widgets_tui::symbols::throbber::BRAILLE_SIX_DOUBLE;
    let symbols = BRAILLE_SIX_DOUBLE.symbols;
    symbols[(frame_tick as usize / 5) % symbols.len()]
}

pub fn render_toast(frame: &mut Frame, app: &App) {
    let Some((message, kind)) = app.popups.iter().rev().find_map(|p| match p {
        Popup::Toast { message, kind, .. } => Some((message.clone(), kind.clone())),
        _ => None,
    }) else { return };
    let theme = app.theme();
    let fg = match kind {
        ToastKind::Info    => theme.foreground,
        ToastKind::Success => theme.success,
        ToastKind::Error   => theme.error,
    };
    let body = line![" ".fg(fg), message.fg(fg).bold(), " ".fg(fg)];
    let width = body.width() as u16;
    let screen = frame.area();
    if screen.width < width + 2 || screen.height < 3 { return; }
    let area = ratatui::layout::Rect {
        x:      screen.x + screen.width.saturating_sub(width + 1),
        y:      screen.y + screen.height.saturating_sub(2),
        width,
        height: 1,
    };
    frame.render_widget(ratatui::widgets::Clear, area);
    frame.render_widget(Paragraph::new(body), area);
}

fn wrap_lines(text: &str, width: usize) -> alloc::vec::Vec<alloc::string::String> {
    use alloc::string::String;
    if width == 0 || text.is_empty() {
        return alloc::vec![text.to_string()];
    }
    let mut out = alloc::vec::Vec::new();
    for paragraph in text.split('\n') {
        let mut current = String::new();
        for word in paragraph.split_whitespace() {
            if current.is_empty() {
                current = format_word(word, width);
            } else if current.len() + 1 + word.len() <= width {
                current.push(' ');
                current.push_str(word);
            } else {
                out.push(core::mem::take(&mut current));
                current = format_word(word, width);
            }
        }
        if !current.is_empty() { out.push(current); }
    }
    if out.is_empty() { out.push(String::new()); }
    out
}

fn format_word(word: &str, _width: usize) -> alloc::string::String {
    word.to_string()
}
