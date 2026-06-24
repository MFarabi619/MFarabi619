use ratatui::{
    Frame,
    layout::{Alignment, Constraint, Layout, Rect},
    style::*,
    widgets::{Block, BorderType, Paragraph, Wrap},
};

pub const FONT_W: u16 = 10;
pub const FONT_H: u16 = 20;

#[derive(Clone, Copy)]
pub struct TouchState {
    pub x: i32,
    pub y: i32,
    pub pressed: bool,
    pub last_pressed: bool,
}

impl TouchState {
    pub const fn new() -> Self {
        Self {
            x: -1,
            y: -1,
            pressed: false,
            last_pressed: false,
        }
    }

    pub const fn edge(&self) -> bool {
        self.pressed && !self.last_pressed
    }

    pub fn commit(&mut self) {
        self.last_pressed = self.pressed;
    }
}

impl Default for TouchState {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Clone, Copy, Debug)]
pub enum Action {
    LedOff,
    Reboot,
}

pub fn render_app(frame: &mut Frame, touch: &TouchState) -> Option<Action> {
    let [top, bottom] =
        Layout::vertical([Constraint::Ratio(1, 2); 2]).areas(frame.area());

    let top_hit = cell_rect_contains_pixel(top, touch.x, touch.y);
    let bot_hit = cell_rect_contains_pixel(bottom, touch.x, touch.y);

    render_button(frame, top, "LED OFF", touch.pressed && top_hit);
    render_button(frame, bottom, "REBOOT", touch.pressed && bot_hit);

    if touch.edge() {
        if top_hit {
            Some(Action::LedOff)
        } else if bot_hit {
            Some(Action::Reboot)
        } else {
            None
        }
    } else {
        None
    }
}

fn cell_rect_contains_pixel(rect: Rect, px: i32, py: i32) -> bool {
    if px < 0 || py < 0 {
        return false;
    }
    let px = px as u16;
    let py = py as u16;
    let x_lo = rect.x * FONT_W;
    let y_lo = rect.y * FONT_H;
    let x_hi = x_lo + rect.width * FONT_W;
    let y_hi = y_lo + rect.height * FONT_H;
    px >= x_lo && px < x_hi && py >= y_lo && py < y_hi
}

fn render_button(frame: &mut Frame, area: Rect, label: &str, highlight: bool) {
    let (fg, bg) = if highlight {
        (Color::Black, Color::Yellow)
    } else {
        (Color::White, Color::Reset)
    };
    let block = Block::bordered()
        .border_type(BorderType::Double)
        .border_style(Style::new().fg(Color::Yellow));
    let paragraph = Paragraph::new(label)
        .alignment(Alignment::Center)
        .style(Style::default().fg(fg).bg(bg))
        .block(block)
        .wrap(Wrap { trim: true });
    frame.render_widget(paragraph, area);
}
