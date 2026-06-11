use alloc::{format, string::{String, ToString}, vec, vec::Vec};
use ratatui::{
    style::{Color, Style, Stylize},
    text::{Line, Span},
    widgets::{Block, Paragraph},
};
use throbber_widgets_tui::symbols::throbber::BRAILLE_SIX_DOUBLE;

use crate::theme::Theme;

pub fn spinner_char(frame_tick: u32) -> &'static str {
    let symbols = BRAILLE_SIX_DOUBLE.symbols;
    symbols[(frame_tick as usize / 5) % symbols.len()]
}

pub fn panel_title(
    theme:           &Theme,
    index_one_based: usize,
    label:           &'static str,
    focused:         bool,
    keep_label_accent: bool,
) -> Line<'static> {
    let chrome = if focused { theme.accent } else { theme.border };
    let label_color = if keep_label_accent { theme.accent } else { chrome };
    let mut number = Span::raw(format!("{index_one_based}")).fg(chrome);
    let mut label_span = Span::raw(label.to_string()).fg(label_color);
    if focused {
        number     = number.bold();
        label_span = label_span.bold();
    }
    Line::from(vec![
        Span::raw("[").fg(chrome),
        number,
        Span::raw("]─").fg(chrome),
        label_span,
    ])
}

pub fn panel_title_tabbed(
    theme:           &Theme,
    index_one_based: usize,
    tab_labels:      &[&str],
    active_index:    usize,
    focused:         bool,
    spinner:         Option<(usize, u32)>,
) -> Line<'static> {
    let chrome = if focused { theme.accent } else { theme.border };
    let number = {
        let span = Span::raw(format!("{index_one_based}")).fg(chrome);
        if focused { span.bold() } else { span }
    };
    let mut spans: Vec<Span<'static>> = vec![
        Span::raw("[").fg(chrome),
        number,
        Span::raw("]─").fg(chrome),
    ];
    for (i, label) in tab_labels.iter().enumerate() {
        if i > 0 {
            spans.push(Span::raw(" ─ ").fg(chrome));
        }
        let style = if i == active_index {
            let s = Style::new().fg(theme.accent);
            if focused { s.bold() } else { s }
        } else {
            Style::new().fg(theme.border)
        };
        spans.push(Span::styled(label.to_string(), style));
        if let Some((spinner_tab, tick)) = spinner {
            if spinner_tab == i {
                spans.push(Span::raw(" "));
                spans.push(Span::raw(spinner_char(tick)).fg(theme.warning).bold());
            }
        }
    }
    Line::from(spans)
}

pub fn tabs_title(
    theme:        &Theme,
    tab_labels:   &[&str],
    active_index: usize,
    focused:      bool,
) -> Line<'static> {
    let chrome = if focused { theme.accent } else { theme.border };
    let number = {
        let span = Span::raw("0").fg(chrome);
        if focused { span.bold() } else { span }
    };
    let mut spans: Vec<Span<'static>> = vec![
        Span::raw("[").fg(chrome),
        number,
        Span::raw("]─").fg(chrome),
    ];
    for (index, label) in tab_labels.iter().enumerate() {
        if index > 0 {
            spans.push(Span::raw(" ─ ").fg(theme.border));
        }
        let style = if index == active_index {
            let s = Style::new().fg(theme.accent);
            if focused { s.bold() } else { s }
        } else {
            Style::new().fg(theme.label)
        };
        spans.push(Span::styled(label.to_string(), style));
    }
    Line::from(spans)
}

pub fn titled_block(theme: &Theme, title: Line<'static>, focused: bool) -> Block<'static> {
    let border_color = if focused { theme.accent } else { theme.border };
    Block::bordered()
        .border_style(Style::new().fg(border_color))
        .title(title)
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
        .border_style(Style::new().fg(border_color))
        .title(title);
    if total > 0 {
        let pos = selected.unwrap_or(0).min(total - 1) + 1;
        let count_color = if focused { theme.accent } else { theme.label };
        let footer = Line::from(vec![
            Span::raw("─").fg(border_color),
            Span::styled(format!("{pos} of {total}"), Style::new().fg(count_color)),
            Span::raw("─").fg(border_color),
        ]).right_aligned();
        block = block.title_bottom(footer);
    }
    block
}

pub fn placeholder_paragraph(theme: &Theme, message: &'static str) -> Paragraph<'static> {
    Paragraph::new(Line::from(Span::styled(message, Style::new().fg(theme.label))))
}

pub fn kv(theme: &Theme, key: &'static str, value: String) -> Line<'static> {
    Line::from(vec![
        Span::raw(format!("{key:<14}")).fg(theme.label),
        Span::raw(value).fg(theme.value).bold(),
    ])
}

pub fn selection_style(theme: &Theme, focused: bool) -> Style {
    if focused {
        Style::new()
            .bg(theme.selection_background)
            .fg(theme.selection_foreground)
            .bold()
    } else {
        Style::new()
    }
}

pub fn selection_symbol(_focused: bool) -> &'static str { "" }

pub fn render_conf_directives(
    frame: &mut ratatui::Frame,
    area:  ratatui::layout::Rect,
    theme: &Theme,
    directives: &[&str],
) {
    use ratatui::widgets::Wrap;
    let lines: Vec<Line<'static>> = directives.iter().map(|line| {
        if let Some((key, value)) = line.split_once('=') {
            Line::from(vec![
                Span::raw(format!("{key}")).fg(theme.value).bold(),
                Span::raw("=").fg(theme.border),
                Span::raw(value.to_string()).fg(theme.accent).bold(),
            ])
        } else {
            Line::from(Span::raw(line.to_string()).fg(theme.value))
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
            spans.push(Span::raw(source[from..to].to_string()).fg(theme.foreground));
        }
    };

    while cursor < bytes.len() {
        let rest = &line[cursor..];

        if let Some(end) = match_bracket_timestamp(rest) {
            flush_plain(&mut spans, line, plain_start, cursor);
            spans.push(Span::raw(line[cursor..cursor + end].to_string()).fg(theme.label));
            cursor += end;
            plain_start = cursor;
            continue;
        }

        if let Some((end, color, bold)) = match_log_level(rest, theme) {
            flush_plain(&mut spans, line, plain_start, cursor);
            let mut span = Span::raw(line[cursor..cursor + end].to_string()).fg(color);
            if bold { span = span.bold(); }
            spans.push(span);
            cursor += end;
            plain_start = cursor;
            continue;
        }

        if let Some(end) = match_ipv4(rest) {
            flush_plain(&mut spans, line, plain_start, cursor);
            spans.push(Span::raw(line[cursor..cursor + end].to_string()).fg(theme.accent));
            cursor += end;
            plain_start = cursor;
            continue;
        }

        if let Some(end) = match_clock_timestamp(rest) {
            flush_plain(&mut spans, line, plain_start, cursor);
            spans.push(Span::raw(line[cursor..cursor + end].to_string()).fg(theme.label));
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
