use std::collections::VecDeque;

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use ratatui::{
    layout::{Constraint, Flex, Layout, Rect},
    style::{Style, Stylize},
    text::{Line, Span},
    widgets::{Block, BorderType, Paragraph},
    Frame,
};

use crate::theme;

const SCOPE_LEN: usize = 60;
const KEYS: [[char; 3]; 3] = [['u', 'i', 'o'], ['j', 'k', 'l'], ['m', ',', '.']];
const BLOCKS: [char; 9] = [' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];

/// A pad command, medium-independent, mirroring the ESP32 `pad.zig` model:
/// each axis is a discrete direction in {-1, 0, 1}.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Command {
    pub linear: i8,
    pub angular: i8,
}

impl Command {
    pub const STOP: Self = Self { linear: 0, angular: 0 };
}

/// Whether the terminal reports key-release events. With them we drive only
/// while a key is held; without them we fall back to sticky teleop-twist behavior.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Hold,
    Sticky,
}

impl Mode {
    fn label(self) -> &'static str {
        match self {
            Mode::Hold => "hold-to-drive",
            Mode::Sticky => "sticky · k stops",
        }
    }
}

/// The 3×3 cluster + arrow keys, mapped to a pad direction. Corners are
/// diff-drive arcs (linear and angular together), `k`/space is an explicit stop.
pub fn command_for(code: KeyCode) -> Option<Command> {
    let cmd = |linear, angular| Some(Command { linear, angular });
    match code {
        KeyCode::Char('i') | KeyCode::Char('I') | KeyCode::Up => cmd(1, 0),
        KeyCode::Char(',') | KeyCode::Char('<') | KeyCode::Down => cmd(-1, 0),
        KeyCode::Char('j') | KeyCode::Char('J') | KeyCode::Left => cmd(0, 1),
        KeyCode::Char('l') | KeyCode::Char('L') | KeyCode::Right => cmd(0, -1),
        KeyCode::Char('u') | KeyCode::Char('U') => cmd(1, 1),
        KeyCode::Char('o') | KeyCode::Char('O') => cmd(1, -1),
        KeyCode::Char('m') | KeyCode::Char('M') => cmd(-1, 1),
        KeyCode::Char('.') | KeyCode::Char('>') => cmd(-1, -1),
        KeyCode::Char('k') | KeyCode::Char('K') | KeyCode::Char(' ') => cmd(0, 0),
        _ => None,
    }
}

pub struct Teleop {
    pub command: Command,
    pub linear_limit: f64,
    pub angular_limit: f64,
    pub mode: Mode,
    pub topic: String,
    pub should_quit: bool,
    pub sent: u64,
    scope: VecDeque<(f64, f64)>,
}

impl Teleop {
    pub fn new(topic: String, linear_limit: f64, angular_limit: f64, mode: Mode) -> Self {
        Self {
            command: Command::STOP,
            linear_limit,
            angular_limit,
            mode,
            topic,
            should_quit: false,
            sent: 0,
            scope: VecDeque::with_capacity(SCOPE_LEN),
        }
    }

    /// The commanded velocity in SI units: pad direction scaled by the limits.
    pub fn velocity(&self) -> (f64, f64) {
        (
            f64::from(self.command.linear) * self.linear_limit,
            f64::from(self.command.angular) * self.angular_limit,
        )
    }

    pub fn is_moving(&self) -> bool {
        self.command != Command::STOP
    }

    pub fn record(&mut self, linear: f64, angular: f64) {
        if self.scope.len() == SCOPE_LEN {
            self.scope.pop_front();
        }
        self.scope.push_back((linear, angular));
    }

    fn bump_linear(&mut self, factor: f64) {
        self.linear_limit = (self.linear_limit * factor).clamp(0.05, 4.0);
    }

    fn bump_angular(&mut self, factor: f64) {
        self.angular_limit = (self.angular_limit * factor).clamp(0.05, 4.0);
    }

    pub fn handle_key(&mut self, key: KeyEvent) {
        if key.is_repeat() {
            return;
        }
        let released = key.is_release();
        match key.code {
            KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                self.should_quit = true;
            }
            KeyCode::Char('q') | KeyCode::Char('Q') if !released => self.should_quit = true,
            KeyCode::Char('+') | KeyCode::Char('=') if !released => self.bump_linear(1.1),
            KeyCode::Char('-') | KeyCode::Char('_') if !released => self.bump_linear(1.0 / 1.1),
            KeyCode::Char(']') if !released => self.bump_angular(1.1),
            KeyCode::Char('[') if !released => self.bump_angular(1.0 / 1.1),
            code => {
                if let Some(command) = command_for(code) {
                    if released {
                        // In hold mode a lifted key means "let go" → stop; sticky ignores releases.
                        if self.mode == Mode::Hold {
                            self.command = Command::STOP;
                        }
                    } else {
                        self.command = command;
                    }
                }
            }
        }
    }
}

pub fn draw(frame: &mut Frame, teleop: &Teleop) {
    let [title, pad, gauges, scope, status] = Layout::vertical([
        Constraint::Length(1),
        Constraint::Min(12),
        Constraint::Length(2),
        Constraint::Length(2),
        Constraint::Length(1),
    ])
    .areas(frame.area());

    frame.render_widget(
        Paragraph::new(Line::from(format!(" lazyros · {} ", teleop.topic)).fg(theme::ACCENT).bold())
            .centered(),
        title,
    );
    draw_pad(frame, pad, teleop);
    draw_gauges(frame, gauges, teleop);
    draw_scope(frame, scope, teleop);

    let hint = format!(
        " {} · +/− linear · [ ] angular · q quit · sent {} ",
        teleop.mode.label(),
        teleop.sent
    );
    frame.render_widget(
        Paragraph::new(Line::from(hint).fg(theme::STATUS)).centered(),
        status,
    );
}

fn draw_pad(frame: &mut Frame, area: Rect, teleop: &Teleop) {
    let rows = Layout::vertical([Constraint::Length(4); 3])
        .flex(Flex::Center)
        .split(area);
    for (row, row_area) in rows.iter().enumerate() {
        let cols = Layout::horizontal([Constraint::Length(7); 3])
            .flex(Flex::Center)
            .split(*row_area);
        for (col, cell_area) in cols.iter().enumerate() {
            keycap(frame, *cell_area, row, col, teleop);
        }
    }
}

fn keycap(frame: &mut Frame, area: Rect, row: usize, col: usize, teleop: &Teleop) {
    let cell_linear = 1 - row as i8;
    let cell_angular = 1 - col as i8;
    let is_stop = row == 1 && col == 1;
    let is_active =
        teleop.command.linear == cell_linear && teleop.command.angular == cell_angular;

    let border_color = if is_active {
        theme::ACTIVE_BORDER
    } else {
        theme::CELL_BORDER
    };
    let glyph_color = if is_stop { theme::STOP } else { theme::ARROW };
    let mut glyph = Span::from(pad_glyph(col as i8 - 1, row as i8 - 1)).fg(glyph_color);
    if is_active {
        glyph = glyph.bold();
    }

    let block = Block::bordered()
        .border_type(BorderType::Rounded)
        .border_style(Style::new().fg(border_color));
    let body = Paragraph::new(vec![
        Line::from(glyph).centered(),
        Line::from(Span::from(KEYS[row][col].to_string()).fg(theme::STATUS)).centered(),
    ])
    .block(block);
    frame.render_widget(body, area);
}

fn pad_glyph(dx: i8, dy: i8) -> &'static str {
    match (dx, dy) {
        (-1, -1) => "↖",
        (0, -1) => "↑",
        (1, -1) => "↗",
        (-1, 0) => "←",
        (0, 0) => "○",
        (1, 0) => "→",
        (-1, 1) => "↙",
        (0, 1) => "↓",
        (1, 1) => "↘",
        _ => "?",
    }
}

fn draw_gauges(frame: &mut Frame, area: Rect, teleop: &Teleop) {
    let (linear, angular) = teleop.velocity();
    let lines = vec![
        gauge_line("linear.x ", linear, teleop.linear_limit, "m/s"),
        gauge_line("angular.z", angular, teleop.angular_limit, "rad/s"),
    ];
    frame.render_widget(Paragraph::new(lines), area);
}

fn gauge_line<'a>(label: &'a str, value: f64, limit: f64, unit: &'a str) -> Line<'a> {
    let color = if value >= 0.0 {
        theme::POSITIVE
    } else {
        theme::NEGATIVE
    };
    Line::from(vec![
        Span::from(format!("  {label} ")).fg(theme::STATUS),
        Span::from("[").fg(theme::FRAME),
        Span::from(signed_bar(value, limit, 26)).fg(color),
        Span::from("] ").fg(theme::FRAME),
        Span::from(format!("{value:+.2} {unit}")).fg(color),
    ])
}

fn signed_bar(value: f64, limit: f64, width: usize) -> String {
    let half = width / 2;
    let ratio = if limit > 0.0 {
        (value / limit).clamp(-1.0, 1.0)
    } else {
        0.0
    };
    let filled = (ratio.abs() * half as f64).round() as usize;
    let mut cells = vec!['·'; width];
    if ratio >= 0.0 {
        for offset in 0..filled {
            if let Some(cell) = cells.get_mut(half + offset) {
                *cell = '█';
            }
        }
    } else {
        for offset in 0..filled {
            if let Some(cell) = half.checked_sub(1 + offset).and_then(|i| cells.get_mut(i)) {
                *cell = '█';
            }
        }
    }
    cells.into_iter().collect()
}

fn draw_scope(frame: &mut Frame, area: Rect, teleop: &Teleop) {
    let lines = vec![
        sparkline("scope lin", teleop.scope.iter().map(|s| s.0), teleop.linear_limit),
        sparkline("      ang", teleop.scope.iter().map(|s| s.1), teleop.angular_limit),
    ];
    frame.render_widget(Paragraph::new(lines), area);
}

fn sparkline<'a>(label: &'a str, samples: impl Iterator<Item = f64>, limit: f64) -> Line<'a> {
    let mut spans = vec![Span::from(format!("  {label} ")).fg(theme::STATUS)];
    for value in samples {
        let magnitude = if limit > 0.0 {
            (value.abs() / limit).clamp(0.0, 1.0)
        } else {
            0.0
        };
        let glyph = BLOCKS[(magnitude * (BLOCKS.len() - 1) as f64).round() as usize];
        let color = if value >= 0.0 {
            theme::POSITIVE
        } else {
            theme::ACCENT
        };
        spans.push(Span::from(glyph.to_string()).fg(color));
    }
    Line::from(spans)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn forward_maps_to_positive_linear() {
        assert_eq!(command_for(KeyCode::Char('i')), Some(Command { linear: 1, angular: 0 }));
        assert_eq!(command_for(KeyCode::Up), Some(Command { linear: 1, angular: 0 }));
    }

    #[test]
    fn corner_is_an_arc() {
        assert_eq!(command_for(KeyCode::Char('u')), Some(Command { linear: 1, angular: 1 }));
    }

    #[test]
    fn center_is_stop() {
        assert_eq!(command_for(KeyCode::Char('k')), Some(Command::STOP));
    }

    #[test]
    fn velocity_scales_by_limits() {
        let mut teleop = Teleop::new("t".into(), 0.5, 1.0, Mode::Hold);
        teleop.command = Command { linear: 1, angular: -1 };
        assert_eq!(teleop.velocity(), (0.5, -1.0));
    }

    #[test]
    fn renders_pad_gauges_and_scope() {
        use ratatui::{backend::TestBackend, Terminal};

        let mut teleop = Teleop::new("joy_teleop/cmd_vel".into(), 0.5, 1.0, Mode::Hold);
        teleop.command = Command { linear: 1, angular: 1 }; // forward-left arc
        for _ in 0..10 {
            let (l, a) = teleop.velocity();
            teleop.record(l, a);
        }

        let mut terminal = Terminal::new(TestBackend::new(64, 20)).unwrap();
        terminal.draw(|frame| draw(frame, &teleop)).unwrap();

        let buffer = terminal.backend().buffer().clone();
        let text: String = buffer
            .content()
            .chunks(buffer.area().width as usize)
            .map(|row| row.iter().map(|cell| cell.symbol()).collect::<String>())
            .collect::<Vec<_>>()
            .join("\n");
        println!("\n{text}");

        assert!(text.contains("lazyros · joy_teleop/cmd_vel"));
        assert!(text.contains("linear.x"));
        assert!(text.contains("hold-to-drive"));
        assert!(text.contains('↖')); // the arc glyph
    }

    #[test]
    fn hold_release_stops_but_sticky_holds() {
        let press = KeyEvent::new(KeyCode::Char('i'), KeyModifiers::NONE);
        let mut release = press;
        release.kind = crossterm::event::KeyEventKind::Release;

        let mut hold = Teleop::new("t".into(), 0.5, 1.0, Mode::Hold);
        hold.handle_key(press);
        assert!(hold.is_moving());
        hold.handle_key(release);
        assert!(!hold.is_moving());

        let mut sticky = Teleop::new("t".into(), 0.5, 1.0, Mode::Sticky);
        sticky.handle_key(press);
        sticky.handle_key(release);
        assert!(sticky.is_moving());
    }
}
