use std::{io, time::Duration};

use crossterm::{
    event::{
        Event, EventStream, KeyboardEnhancementFlags, PopKeyboardEnhancementFlags,
        PushKeyboardEnhancementFlags,
    },
    execute,
    terminal::supports_keyboard_enhancement,
};
use futures::StreamExt;
use oxidros::prelude::*;
use ratatui::DefaultTerminal;
use tokio::time::interval;

use lazyros_core::{draw, teleop::Mode, BoxError, CmdVelPublisher, Teleop};

const RATE_HZ: f64 = 20.0;
const SETTLE_TICKS: u32 = 12; // ~0.6 s of zeros on release — outlives the twist_mux 0.5 s timeout

struct Args {
    topic: String,
    frame: String,
    linear: f64,
    angular: f64,
}

fn parse_args() -> Args {
    let mut args = Args {
        topic: "joy_teleop/cmd_vel".to_owned(),
        frame: "base_link".to_owned(),
        linear: 0.5,
        angular: 1.0,
    };
    let mut rest = std::env::args().skip(1);
    while let Some(arg) = rest.next() {
        match arg.as_str() {
            "--frame" => args.frame = rest.next().unwrap_or(args.frame),
            "--linear" => args.linear = rest.next().and_then(|v| v.parse().ok()).unwrap_or(args.linear),
            "--angular" => {
                args.angular = rest.next().and_then(|v| v.parse().ok()).unwrap_or(args.angular)
            }
            other if !other.starts_with('-') => args.topic = other.to_owned(),
            _ => {}
        }
    }
    args
}

#[tokio::main]
async fn main() -> Result<(), BoxError> {
    let args = parse_args();

    let context = match Context::new() {
        Ok(context) => context,
        Err(error) => {
            eprintln!("lazyros: could not open the zenoh session: {error}");
            eprintln!("         needs a router at tcp/localhost:7447 (run `rmw_zenohd`),");
            eprintln!("         or set ZENOH_SESSION_CONFIG_URI to a config pointing at the robot.");
            return Err(error.into());
        }
    };
    let node = context.create_node("lazyros", None)?;
    let publisher = CmdVelPublisher::new(&node, &args.topic, &args.frame)?;

    let mut terminal = ratatui::init();
    let hold_supported = enable_hold_mode();
    let mode = if hold_supported { Mode::Hold } else { Mode::Sticky };
    let mut teleop = Teleop::new(args.topic, args.linear, args.angular, mode);

    let outcome = drive_loop(&mut terminal, &publisher, &mut teleop).await;

    disable_hold_mode(hold_supported);
    ratatui::restore();

    // Guarantee a stop even if we bailed mid-motion (ctrl-c, draw error).
    for _ in 0..SETTLE_TICKS {
        let _ = publisher.send(0.0, 0.0);
    }
    outcome
}

async fn drive_loop(
    terminal: &mut DefaultTerminal,
    publisher: &CmdVelPublisher,
    teleop: &mut Teleop,
) -> Result<(), BoxError> {
    let mut ticker = interval(Duration::from_secs_f64(1.0 / RATE_HZ));
    let mut events = EventStream::new();
    let mut settle: u32 = 0;

    let ctrl_c = tokio::signal::ctrl_c();
    tokio::pin!(ctrl_c);

    terminal.draw(|frame| draw(frame, teleop))?;
    while !teleop.should_quit {
        tokio::select! {
            _ = &mut ctrl_c => break,
            maybe_event = events.next() => {
                match maybe_event {
                    Some(Ok(Event::Key(key))) => {
                        let was_moving = teleop.is_moving();
                        teleop.handle_key(key);
                        if was_moving && !teleop.is_moving() {
                            settle = SETTLE_TICKS;
                        }
                    }
                    Some(Ok(_)) => {}
                    Some(Err(_)) | None => break,
                }
                terminal.draw(|frame| draw(frame, teleop))?;
            }
            _ = ticker.tick() => {
                if teleop.is_moving() {
                    let (linear, angular) = teleop.velocity();
                    publisher.send(linear, angular)?;
                    teleop.sent += 1;
                    teleop.record(linear, angular);
                    settle = SETTLE_TICKS;
                } else if settle > 0 {
                    publisher.send(0.0, 0.0)?;
                    teleop.sent += 1;
                    teleop.record(0.0, 0.0);
                    settle -= 1;
                } else {
                    teleop.record(0.0, 0.0);
                }
                terminal.draw(|frame| draw(frame, teleop))?;
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

fn disable_hold_mode(enabled: bool) {
    if enabled {
        let _ = execute!(io::stdout(), PopKeyboardEnhancementFlags);
    }
}
