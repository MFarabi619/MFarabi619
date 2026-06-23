mod button;
mod chart;
mod gauge;
mod helpers;
mod lorem;
mod ratatui_logo;
mod tabs;
mod voltage;

use std::cell::RefCell;
use std::process;
use std::rc::Rc;
use std::time::Duration;

use embedded_graphics_simulator::{OutputSettings, SimulatorDisplay, SimulatorEvent, Window};
use mousefood::{
    ColorTheme, EmbeddedBackend, EmbeddedBackendConfig,
    embedded_graphics::{geometry, pixelcolor::Bgr565},
    fonts,
};
use ratatui::Terminal;

use crate::button::Button;
use crate::chart::ChartApp;
use crate::gauge::GaugeApp;
use crate::helpers::Delay;
use crate::ratatui_logo::RatatuiLogoApp;
use crate::tabs::TabsApp;
use crate::voltage::VoltageApp;

fn main() {
    let mut window = Window::new(
        "mousefood demo (320x240, CYD-shaped)",
        &OutputSettings {
            scale: 2,
            ..Default::default()
        },
    );
    window.set_max_fps(30);

    let mut display = SimulatorDisplay::<Bgr565>::new(geometry::Size::new(320, 240));

    let events: Rc<RefCell<Vec<SimulatorEvent>>> = Rc::new(RefCell::new(Vec::new()));
    let events_for_callback = events.clone();

    let config = EmbeddedBackendConfig {
        flush_callback: Box::new(move |display| {
            window.update(display);
            let mut buf = events_for_callback.borrow_mut();
            for event in window.events() {
                if let SimulatorEvent::Quit = event {
                    process::exit(0);
                }
                buf.push(event);
            }
        }),
        color_theme: ColorTheme::tokyo_night(),
        font_regular: fonts::mono_8x13_atlas(),
        font_bold: Some(fonts::mono_8x13_bold_atlas()),
        font_italic: Some(fonts::mono_8x13_italic_atlas()),
        ..Default::default()
    };
    let backend = EmbeddedBackend::new(&mut display, config);
    let mut terminal = Terminal::new(backend).expect("Terminal::new");

    let mut button = Button::new(events.clone(), Duration::from_millis(150));
    let delay = Delay::new();

    let mut voltage_t = 0.0f64;
    let mut read_voltage = || {
        voltage_t += 0.05;
        Some((1500.0 + 500.0 * voltage_t.sin()) as u16)
    };

    loop {
        RatatuiLogoApp::new().run(&mut terminal, &mut button, &delay);
        delay.delay_millis(200);

        TabsApp::new().run(&mut terminal, &mut button, &delay);
        delay.delay_millis(200);

        ChartApp::new().run(&mut terminal, &mut button, &delay);
        delay.delay_millis(200);

        GaugeApp::new().run(&mut terminal, &mut button, &delay);
        delay.delay_millis(200);

        VoltageApp::new().run(&mut terminal, &mut button, &delay, &mut read_voltage);
        delay.delay_millis(200);
    }
}
