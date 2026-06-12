use ratatui::{
    Frame,
    layout::Rect,
    style::{Style, Stylize},
    text::Line,
    widgets::{Block, Clear},
};

use crate::theme::Theme;

pub fn render_chrome(frame: &mut Frame, area: Rect, theme: &Theme, title: Line<'static>) -> Rect {
    let block = Block::bordered()
        .border_type(theme.border_type)
        .border_style(Style::new().fg(theme.accent))
        .title(title);
    let inner = block.inner(area);
    frame.render_widget(Clear, area);
    frame.render_widget(block, area);
    inner
}

pub fn chrome_title(theme: &Theme, label: &'static str) -> Line<'static> {
    label.fg(theme.accent).bold().into()
}

pub fn highlight_line(text: &str, indices: &[usize], base: ratatui::style::Style, hl: ratatui::style::Style) -> Line<'static> {
    use alloc::{string::String, vec::Vec};
    use ratatui::text::Span;
    let mut spans: Vec<Span<'static>> = Vec::new();
    let mut buf = String::new();
    let mut current_hl = false;
    for (i, c) in text.chars().enumerate() {
        let want_hl = indices.contains(&i);
        if want_hl != current_hl && !buf.is_empty() {
            spans.push(Span::styled(core::mem::take(&mut buf), if current_hl { hl } else { base }));
        }
        current_hl = want_hl;
        buf.push(c);
    }
    if !buf.is_empty() {
        spans.push(Span::styled(buf, if current_hl { hl } else { base }));
    }
    Line::from(spans)
}
