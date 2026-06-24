use embedded_graphics::pixelcolor::Rgb565;
use embedded_graphics::prelude::*;
use embedded_graphics_simulator::{
    OutputSettingsBuilder, SimulatorDisplay, SimulatorEvent, Window,
};
use mousefood::{EmbeddedBackend, EmbeddedBackendConfig, fonts};
use ratatui::Terminal;

use firmware::ui::{self, Action, TouchState};

const WIDTH: u32 = 240;
const HEIGHT: u32 = 320;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut display = SimulatorDisplay::<Rgb565>::new(Size::new(WIDTH, HEIGHT));
    let output_settings = OutputSettingsBuilder::new().scale(2).build();
    let mut window = Window::new("cyd28 simulator", &output_settings);
    let mut touch = TouchState::new();

    'main: loop {
        let mut action: Option<Action> = None;
        {
            let backend = EmbeddedBackend::new(
                &mut display,
                EmbeddedBackendConfig {
                    font_regular: fonts::mono_10x20_atlas(),
                    ..Default::default()
                },
            );
            let mut terminal = Terminal::new(backend)?;
            terminal.draw(|frame| {
                action = ui::render_app(frame, &touch);
            })?;
        }
        touch.commit();

        match action {
            Some(Action::LedOff) => println!("[sim] LED OFF tapped"),
            Some(Action::Reboot) => {
                println!("[sim] REBOOT tapped — exiting simulator");
                break 'main;
            }
            None => {}
        }

        window.update(&display);

        for event in window.events() {
            match event {
                SimulatorEvent::Quit => break 'main,
                SimulatorEvent::MouseButtonDown { point, .. } => {
                    touch.x = point.x;
                    touch.y = point.y;
                    touch.pressed = true;
                }
                SimulatorEvent::MouseButtonUp { .. } => {
                    touch.pressed = false;
                }
                SimulatorEvent::MouseMove { point } => {
                    if touch.pressed {
                        touch.x = point.x;
                        touch.y = point.y;
                    }
                }
                _ => {}
            }
        }

        std::thread::sleep(std::time::Duration::from_millis(33));
    }

    Ok(())
}
