use alloc::{format, string::{String, ToString}, vec::Vec};
use ratatui::{
    Frame,
    layout::Rect,
    macros::line,
    style::{Color, Style, Stylize},
    text::{Line, Span},
    widgets::{Block, Paragraph, Tabs, Widget},
};

use crate::theme::Theme;

pub fn panel_title(
    theme:           &Theme,
    index_one_based: usize,
    label:           &'static str,
    focused:         bool,
    keep_label_accent: bool,
    show_jumps:      bool,
) -> Line<'static> {
    let chrome = if focused { theme.accent } else { theme.border };
    let label_color = if keep_label_accent { theme.accent } else { chrome };
    let mut label_span = label.to_string().fg(label_color);
    if focused {
        label_span = label_span.bold();
    }
    if !show_jumps {
        return Line::from(label_span);
    }
    let mut number = format!("{index_one_based}").fg(chrome);
    if focused { number = number.bold(); }
    line!["[".fg(chrome), number, "]─".fg(chrome), label_span]
}

pub fn overlay_panel_tabs(
    frame:           &mut Frame,
    area:            Rect,
    theme:           &Theme,
    index_one_based: usize,
    tab_labels:      &[&str],
    active_index:    usize,
    focused:         bool,
    show_jumps:      bool,
) {
    let chrome = if focused { theme.accent } else { theme.border };
    let prefix = if show_jumps {
        let mut number = format!("{index_one_based}").fg(chrome);
        if focused { number = number.bold(); }
        line!["[".fg(chrome), number, "]─".fg(chrome)]
    } else {
        Line::raw("")
    };
    overlay_tabs(frame, area, prefix, tab_labels, active_index, focused, chrome, theme.border, theme.accent);
}

pub fn overlay_detail_tabs(
    frame:        &mut Frame,
    area:         Rect,
    theme:        &Theme,
    tab_labels:   &[&str],
    active_index: usize,
    focused:      bool,
) {
    let chrome = if focused { theme.accent } else { theme.border };
    let mut number = "0".fg(chrome);
    if focused { number = number.bold(); }
    let prefix = line!["[".fg(chrome), number, "]─".fg(chrome)];
    overlay_tabs(frame, area, prefix, tab_labels, active_index, focused, theme.border, theme.label, theme.accent);
}

fn overlay_tabs(
    frame:           &mut Frame,
    area:            Rect,
    prefix:          Line<'static>,
    tab_labels:      &[&str],
    active_index:    usize,
    focused:         bool,
    divider_color:   Color,
    unselected_color: Color,
    selected_color:  Color,
) {
    if area.width < 4 { return; }
    let prefix_w = prefix.width() as u16;
    {
        let buf = frame.buffer_mut();
        buf.set_line(area.x + 1, area.y, &prefix, area.width.saturating_sub(2));
    }
    let tabs_x = area.x + 1 + prefix_w;
    let tabs_width = area.width.saturating_sub(prefix_w + 2);
    if tabs_width == 0 { return; }
    let tabs_area = Rect { x: tabs_x, y: area.y, width: tabs_width, height: 1 };

    let titles: Vec<Line<'static>> = tab_labels.iter()
        .map(|s| Line::from(s.to_string().fg(unselected_color)))
        .collect();
    let highlight = {
        let s = Style::new().fg(selected_color);
        if focused { s.bold() } else { s }
    };
    let tabs = Tabs::new(titles)
        .select(active_index)
        .padding("", "")
        .divider(Span::from(" ─ ").fg(divider_color))
        .highlight_style(highlight);
    Widget::render(tabs, tabs_area, frame.buffer_mut());
}

pub fn titled_list_block(
    theme:    &Theme,
    title:    Line<'static>,
    focused:  bool,
    selected: Option<usize>,
    total:    usize,
) -> Block<'static> {
    let border_color = if focused { theme.accent } else { theme.border };
    let mut block = Block::bordered()
        .border_type(theme.border_type)
        .border_style(Style::new().fg(border_color))
        .title(title);
    if total > 0 {
        let pos = selected.unwrap_or(0).min(total - 1) + 1;
        let count_color = if focused { theme.accent } else { theme.label };
        let footer = line![
            "─".fg(border_color),
            format!("{pos} of {total}").fg(count_color),
            "─".fg(border_color),
        ].right_aligned();
        block = block.title_bottom(footer);
    }
    block
}

pub fn placeholder_paragraph(theme: &Theme, message: &'static str) -> Paragraph<'static> {
    Paragraph::new(Line::from(message.fg(theme.label)))
}

pub fn kv(theme: &Theme, key: &'static str, value: String) -> Line<'static> {
    line![format!("{key:<14}").fg(theme.label), value.fg(theme.value).bold()]
}

pub fn selection_style(theme: &Theme, focused: bool) -> Style {
    let bg = if focused { theme.selection_background } else { theme.selection_background_inactive };
    Style::new().bg(bg)
}

pub fn selection_symbol(_focused: bool) -> &'static str { "" }

pub fn render_conf_directives(
    frame: &mut ratatui::Frame,
    area:  ratatui::layout::Rect,
    theme: &Theme,
    directives: &[&str],
) {
    use ratatui::widgets::Wrap;
    let lines: Vec<Line<'static>> = directives.iter().map(|l| {
        if let Some((key, value)) = l.split_once('=') {
            line![
                key.to_string().fg(theme.value).bold(),
                "=".fg(theme.border),
                value.to_string().fg(theme.accent).bold(),
            ]
        } else {
            Line::from(l.to_string().fg(theme.value))
        }
    }).collect();
    frame.render_widget(Paragraph::new(lines).wrap(Wrap { trim: false }), area);
}

pub fn highlight_log_line(theme: &Theme, line: &str) -> Line<'static> {
    let bytes = line.as_bytes();
    let mut spans: Vec<Span<'static>> = Vec::new();
    let mut plain_start = 0usize;
    let mut cursor = 0usize;

    let flush_plain = |spans: &mut Vec<Span<'static>>, source: &str, from: usize, to: usize| {
        if to > from {
            spans.push(source[from..to].to_string().fg(theme.foreground));
        }
    };

    while cursor < bytes.len() {
        let rest = &line[cursor..];

        if let Some(end) = match_bracket_timestamp(rest) {
            flush_plain(&mut spans, line, plain_start, cursor);
            spans.push(line[cursor..cursor + end].to_string().fg(theme.label));
            cursor += end;
            plain_start = cursor;
            continue;
        }

        if let Some((end, color, bold)) = match_log_level(rest, theme) {
            flush_plain(&mut spans, line, plain_start, cursor);
            let mut span = line[cursor..cursor + end].to_string().fg(color);
            if bold { span = span.bold(); }
            spans.push(span);
            cursor += end;
            plain_start = cursor;
            continue;
        }

        if let Some(end) = match_ipv4(rest) {
            flush_plain(&mut spans, line, plain_start, cursor);
            spans.push(line[cursor..cursor + end].to_string().fg(theme.accent));
            cursor += end;
            plain_start = cursor;
            continue;
        }

        if let Some(end) = match_clock_timestamp(rest) {
            flush_plain(&mut spans, line, plain_start, cursor);
            spans.push(line[cursor..cursor + end].to_string().fg(theme.label));
            cursor += end;
            plain_start = cursor;
            continue;
        }

        cursor += rest.chars().next().map(char::len_utf8).unwrap_or(1);
    }

    flush_plain(&mut spans, line, plain_start, cursor);
    Line::from(spans)
}

fn match_bracket_timestamp(rest: &str) -> Option<usize> {
    let bytes = rest.as_bytes();
    if bytes.first() != Some(&b'[') { return None; }
    let close = bytes.iter().position(|&b| b == b']')?;
    let inside = &rest[1..close];
    if inside.chars().all(|c| matches!(c, '0'..='9' | ':' | '.' | ',' | ' ' | '+' | '-')) {
        Some(close + 1)
    } else {
        None
    }
}

fn match_clock_timestamp(rest: &str) -> Option<usize> {
    let bytes = rest.as_bytes();
    if bytes.len() < 8 { return None; }
    let pattern_ok = bytes[..8].iter().enumerate().all(|(index, byte)| match index {
        2 | 5 => *byte == b':',
        _     => byte.is_ascii_digit(),
    });
    if !pattern_ok { return None; }
    let mut end = 8;
    if bytes.get(end) == Some(&b'.') {
        end += 1;
        while end < bytes.len() && bytes[end].is_ascii_digit() { end += 1; }
    }
    Some(end)
}

fn match_ipv4(rest: &str) -> Option<usize> {
    let bytes = rest.as_bytes();
    let mut cursor = 0usize;
    for octet_index in 0..4 {
        let start = cursor;
        while cursor < bytes.len() && bytes[cursor].is_ascii_digit() { cursor += 1; }
        let digits = cursor - start;
        if digits == 0 || digits > 3 { return None; }
        if octet_index < 3 {
            if bytes.get(cursor) != Some(&b'.') { return None; }
            cursor += 1;
        }
    }
    Some(cursor)
}

fn match_log_level(rest: &str, theme: &Theme) -> Option<(usize, Color, bool)> {
    const ZEPHYR_LEVELS: &[(&str, fn(&Theme) -> Color, bool)] = &[
        ("<inf>", |t| t.success, false),
        ("<wrn>", |t| t.warning, true),
        ("<err>", |t| t.error,   true),
        ("<dbg>", |t| t.label,   false),
    ];
    for (token, color_for, bold) in ZEPHYR_LEVELS {
        if rest.starts_with(token) {
            return Some((token.len(), color_for(theme), *bold));
        }
    }
    const CAPS_LEVELS: &[(&str, fn(&Theme) -> Color, bool)] = &[
        ("CRITICAL", |t| t.error,   true),
        ("FATAL",    |t| t.error,   true),
        ("ERROR",    |t| t.error,   true),
        ("ERR",      |t| t.error,   true),
        ("WARNING",  |t| t.warning, true),
        ("WARN",     |t| t.warning, true),
        ("INFO",     |t| t.success, false),
        ("DEBUG",    |t| t.label,   false),
        ("TRACE",    |t| t.label,   false),
    ];
    for (token, color_for, bold) in CAPS_LEVELS {
        if rest.starts_with(token) {
            let next_byte = rest.as_bytes().get(token.len());
            let next_is_word = matches!(next_byte, Some(b) if b.is_ascii_alphanumeric() || *b == b'_');
            if !next_is_word {
                return Some((token.len(), color_for(theme), *bold));
            }
        }
    }
    None
}
