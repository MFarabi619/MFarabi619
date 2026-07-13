use std::{
    io,
    process::{Command, Stdio},
    time::Duration,
};

use ratatui::{
    crossterm::{
        event::{
            self, KeyCode, KeyModifiers, KeyboardEnhancementFlags, PopKeyboardEnhancementFlags,
            PushKeyboardEnhancementFlags,
        },
        execute,
        terminal::supports_keyboard_enhancement,
    },
    layout::{Constraint, Flex, Layout, Rect},
    style::{Color, Style, Stylize},
    widgets::{Block, BorderType, Paragraph},
    DefaultTerminal, Frame,
};

type BoxError = Box<dyn std::error::Error + Send + Sync>;

const DEFAULT_ADDRESS: &str = "10.0.0.21";
const GPIO_DEVICE: &str = "gpio0";
const PWM_DEVICE: &str = "ledc@60019000";
const LEFT_PWM_CHANNEL: u8 = 0;
const RIGHT_PWM_CHANNEL: u8 = 1;
const LEFT_DIR_PIN: u8 = 2;
const RIGHT_DIR_PIN: u8 = 7;
const PWM_PERIOD_US: u32 = 50;
const PWM_DUTY_US: u32 = PWM_PERIOD_US;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Direction {
    Forward,
    Backward,
    Left,
    Right,
}

impl Direction {
    fn of(code: KeyCode) -> Option<Self> {
        match code {
            KeyCode::Up => Some(Direction::Forward),
            KeyCode::Down => Some(Direction::Backward),
            KeyCode::Left => Some(Direction::Left),
            KeyCode::Right => Some(Direction::Right),
            _ => None,
        }
    }

    fn levels(self) -> (u8, u8) {
        match self {
            Direction::Forward => (1, 0),
            Direction::Backward => (0, 1),
            Direction::Left => (0, 0),
            Direction::Right => (1, 1),
        }
    }

    fn readout(self) -> (f64, f64) {
        match self {
            Direction::Forward => (1.0, 0.0),
            Direction::Backward => (-1.0, 0.0),
            Direction::Left => (0.0, 1.0),
            Direction::Right => (0.0, -1.0),
        }
    }
}

struct Teleop {
    active: Option<Direction>,
    should_quit: bool,
}

impl Teleop {
    fn new() -> Self {
        Self {
            active: None,
            should_quit: false,
        }
    }
}

fn shell(address: &str, command: &str) -> io::Result<()> {
    Command::new("mcumgrctl")
        .args(["--udp", address, "shell", command])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()?;
    Ok(())
}

fn stop(address: &str) -> io::Result<()> {
    shell(
        address,
        &format!("pwm usec {PWM_DEVICE} {LEFT_PWM_CHANNEL} {PWM_PERIOD_US} 0"),
    )?;
    shell(
        address,
        &format!("pwm usec {PWM_DEVICE} {RIGHT_PWM_CHANNEL} {PWM_PERIOD_US} 0"),
    )
}

fn drive(address: &str, direction: Direction) -> io::Result<()> {
    let (left_level, right_level) = direction.levels();
    shell(
        address,
        &format!("gpio conf {GPIO_DEVICE} {LEFT_DIR_PIN} o{left_level}"),
    )?;
    shell(
        address,
        &format!("gpio conf {GPIO_DEVICE} {RIGHT_DIR_PIN} o{right_level}"),
    )?;
    shell(
        address,
        &format!("pwm usec {PWM_DEVICE} {LEFT_PWM_CHANNEL} {PWM_PERIOD_US} {PWM_DUTY_US}"),
    )?;
    shell(
        address,
        &format!("pwm usec {PWM_DEVICE} {RIGHT_PWM_CHANNEL} {PWM_PERIOD_US} {PWM_DUTY_US}"),
    )
}

fn draw(frame: &mut Frame, teleop: &Teleop) {
    let [pad, status] =
        Layout::vertical([Constraint::Min(0), Constraint::Length(1)]).areas(frame.area());

    let [top, bottom] = Layout::vertical([Constraint::Length(3); 2])
        .flex(Flex::Center)
        .areas(pad);
    let [_, up, _] = Layout::horizontal([Constraint::Length(7); 3])
        .flex(Flex::Center)
        .areas(top);
    let [left, down, right] = Layout::horizontal([Constraint::Length(7); 3])
        .flex(Flex::Center)
        .areas(bottom);

    keycap(frame, up, "↑", teleop.active == Some(Direction::Forward));
    keycap(frame, left, "←", teleop.active == Some(Direction::Left));
    keycap(frame, down, "↓", teleop.active == Some(Direction::Backward));
    keycap(frame, right, "→", teleop.active == Some(Direction::Right));

    let (linear, angular) = teleop.active.map_or((0.0, 0.0), Direction::readout);
    let readout = format!("linear {linear:+.2}  angular {angular:+.2}");
    frame.render_widget(Paragraph::new(readout).centered().dim(), status);
}

fn keycap(frame: &mut Frame, area: Rect, glyph: &str, is_active: bool) {
    let color = if is_active {
        Color::Green
    } else {
        Color::DarkGray
    };
    let block = Block::bordered()
        .border_type(BorderType::Rounded)
        .border_style(Style::new().fg(color));
    frame.render_widget(
        Paragraph::new(glyph).centered().fg(color).block(block),
        area,
    );
}

fn drive_loop(
    terminal: &mut DefaultTerminal,
    teleop: &mut Teleop,
    address: &str,
) -> Result<(), BoxError> {
    while !teleop.should_quit {
        terminal.draw(|frame| draw(frame, teleop))?;
        if !event::poll(Duration::from_millis(100))? {
            continue;
        }
        let Some(key) = event::read()?.as_key_event() else {
            continue;
        };
        if key.is_repeat() {
            continue; // one drive command per hold, not a flood of mcumgrctl round-trips
        }
        if key.is_release() {
            teleop.active = None;
            stop(address)?;
            continue;
        }
        match key.code {
            KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                teleop.should_quit = true;
            }
            KeyCode::Char('q') => teleop.should_quit = true,
            code => {
                if let Some(direction) = Direction::of(code) {
                    teleop.active = Some(direction);
                    drive(address, direction)?;
                }
            }
        }
    }
    Ok(())
}

fn enable_hold_mode() -> bool {
    if supports_keyboard_enhancement().unwrap_or(false) {
        let _ = execute!(
            io::stdout(),
            PushKeyboardEnhancementFlags(KeyboardEnhancementFlags::REPORT_EVENT_TYPES)
        );
        true
    } else {
        false
    }
}

fn disable_hold_mode(hold_mode: bool) {
    if hold_mode {
        let _ = execute!(io::stdout(), PopKeyboardEnhancementFlags);
    }
}

fn main() -> Result<(), BoxError> {
    let address = std::env::args()
        .nth(1)
        .unwrap_or_else(|| DEFAULT_ADDRESS.to_string());

    let mut teleop = Teleop::new();
    let outcome = ratatui::run(|terminal| {
        let hold_mode = enable_hold_mode();
        let result = drive_loop(terminal, &mut teleop, &address);
        disable_hold_mode(hold_mode);
        result
    });

    let _ = stop(&address);
    outcome
}
