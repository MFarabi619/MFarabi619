use std::{io, time::Duration};

use futures_util::StreamExt;
use ratatui::{
    crossterm::{
        event::{
            EventStream, KeyCode, KeyModifiers, KeyboardEnhancementFlags,
            PopKeyboardEnhancementFlags, PushKeyboardEnhancementFlags,
        },
        execute,
        terminal::supports_keyboard_enhancement,
    },
    layout::{Constraint, Flex, Layout},
    style::Stylize,
    widgets::Paragraph,
    DefaultTerminal, Frame,
};
use robot::config::{HOST, I2C_BUS, PCA9685_ADDRESS, RGPIOD_PORT};
use robot_drivers::{gpio::Connection, i2c::I2c, pca9685::Pca9685};

type BoxError = Box<dyn std::error::Error + Send + Sync>;

const TILT_CHANNEL: u8 = 0;
const PAN_CHANNEL: u8 = 1;

const CENTER_DEG: f64 = 90.0;
const MINIMUM_DEG: f64 = 0.0;
const MAXIMUM_DEG: f64 = 180.0;

const CONTROL_HZ: f64 = 60.0;
const LEAD_DEG: f64 = 6.0;
const SLEW_DEG_PER_TICK: f64 = 1.5;

struct Camera {
    tilt: f64,
    pan: f64,
    tilt_target: f64,
    pan_target: f64,
    should_quit: bool,
}

impl Camera {
    fn new() -> Self {
        Self {
            tilt: CENTER_DEG,
            pan: CENTER_DEG,
            tilt_target: CENTER_DEG,
            pan_target: CENTER_DEG,
            should_quit: false,
        }
    }

    fn press(&mut self, code: KeyCode) {
        match code {
            KeyCode::Up => self.tilt_target = (self.tilt + LEAD_DEG).min(MAXIMUM_DEG),
            KeyCode::Down => self.tilt_target = (self.tilt - LEAD_DEG).max(MINIMUM_DEG),
            KeyCode::Left => self.pan_target = (self.pan + LEAD_DEG).min(MAXIMUM_DEG),
            KeyCode::Right => self.pan_target = (self.pan - LEAD_DEG).max(MINIMUM_DEG),
            KeyCode::Char(' ') => {
                self.tilt_target = CENTER_DEG;
                self.pan_target = CENTER_DEG;
            }
            KeyCode::Char('q') => self.should_quit = true,
            _ => {}
        }
    }

    fn ease(&mut self) -> bool {
        let (tilt, pan) = (self.tilt, self.pan);
        self.tilt += (self.tilt_target - self.tilt).clamp(-SLEW_DEG_PER_TICK, SLEW_DEG_PER_TICK);
        self.pan += (self.pan_target - self.pan).clamp(-SLEW_DEG_PER_TICK, SLEW_DEG_PER_TICK);
        self.tilt != tilt || self.pan != pan
    }
}

fn aim(pca9685: &Pca9685, camera: &Camera) -> Result<(), BoxError> {
    pca9685.set_servo_angle(TILT_CHANNEL, camera.tilt)?;
    pca9685.set_servo_angle(PAN_CHANNEL, camera.pan)?;
    Ok(())
}

fn draw(frame: &mut Frame, camera: &Camera) {
    let [pad, help] =
        Layout::vertical([Constraint::Min(0), Constraint::Length(1)]).areas(frame.area());
    let [line] = Layout::vertical([Constraint::Length(1)])
        .flex(Flex::Center)
        .areas(pad);

    let readout = format!(
        "tilt  ↑↓  {:>5.0}°        pan  ←→  {:>5.0}°",
        camera.tilt, camera.pan
    );
    frame.render_widget(Paragraph::new(readout).centered().bold(), line);

    let controls = "arrows aim · space center · q quit";
    frame.render_widget(Paragraph::new(controls).centered().dim(), help);
}

async fn control_loop(
    terminal: &mut DefaultTerminal,
    camera: &mut Camera,
    pca9685: &Pca9685<'_>,
) -> Result<(), BoxError> {
    let mut events = EventStream::new();
    let mut control = tokio::time::interval(Duration::from_secs_f64(1.0 / CONTROL_HZ));
    aim(pca9685, camera)?;
    terminal.draw(|frame| draw(frame, camera))?;
    while !camera.should_quit {
        tokio::select! {
            maybe_event = events.next() => {
                let Some(event) = maybe_event else { break };
                let Some(key) = event?.as_key_event() else { continue };
                if key.code == KeyCode::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL) {
                    camera.should_quit = true;
                } else if !key.is_release() {
                    camera.press(key.code);
                }
            }
            _ = control.tick() => {
                if camera.ease() {
                    aim(pca9685, camera)?;
                    terminal.draw(|frame| draw(frame, camera))?;
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

#[tokio::main]
async fn main() -> Result<(), BoxError> {
    let connection = Connection::connect(HOST, RGPIOD_PORT)?;
    let i2c = I2c::open(&connection, I2C_BUS, PCA9685_ADDRESS)?;
    let pca9685 = Pca9685::new(i2c)?;

    let mut terminal = ratatui::init();
    let hold_mode = enable_hold_mode();
    let mut camera = Camera::new();
    let outcome = control_loop(&mut terminal, &mut camera, &pca9685).await;
    disable_hold_mode(hold_mode);
    ratatui::restore();

    outcome
}
