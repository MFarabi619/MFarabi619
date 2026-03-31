use std::io;

mod app;
mod effects;
mod ui;

use app::App;

#[cfg(not(target_arch = "wasm32"))]
use {
    crossterm::event::{self, Event, KeyCode, KeyEventKind},
    ratatui::DefaultTerminal,
    std::time::Duration,
};

#[cfg(target_arch = "wasm32")]
use ratzilla::{
    CanvasBackend, WebRenderer,
    event::KeyCode,
    ratatui::{Terminal, style::Color},
};

#[cfg(not(target_arch = "wasm32"))]
fn handle_key_code(app: &mut App, key_code: KeyCode) {
    match key_code {
        KeyCode::Right => app.on_right(),
        KeyCode::Left => app.on_left(),
        KeyCode::Up => app.on_up(),
        KeyCode::Down => app.on_down(),
        KeyCode::Char(character) => app.on_key(character),
        _ => {}
    }
}

#[cfg(not(target_arch = "wasm32"))]
fn run_native(app: &mut App, terminal: &mut DefaultTerminal) -> io::Result<()> {
    while !app.should_quit {
        if event::poll(Duration::from_millis(16))?
            && let Event::Key(key_event) = event::read()?
            && key_event.kind == KeyEventKind::Press
        {
            handle_key_code(app, key_event.code);
        }

        let elapsed = app.on_tick();
        terminal.draw(|frame| ui::draw(elapsed, frame, app))?;
    }

    Ok(())
}

#[cfg(not(target_arch = "wasm32"))]
fn main() -> io::Result<()> {
    let mut terminal = ratatui::init();
    let mut app = App::new(" 🔱 Mumtahin Farabi 🔱 ", false);
    let app_result = run_native(&mut app, &mut terminal);
    ratatui::restore();
    app_result
}

#[cfg(target_arch = "wasm32")]
fn main() -> io::Result<()> {
    let app_state = std::rc::Rc::new(std::cell::RefCell::new(App::new(
        " 🔱 Mumtahin Farabi 🔱 ",
        false,
    )));

    let mut backend = CanvasBackend::new()?;
    backend.set_background_color(Color::Rgb(1, 1, 1));
    let terminal = Terminal::new(backend)?;

    terminal.on_key_event({
        let app_state = app_state.clone();
        move |event| {
            let mut app = app_state.borrow_mut();
            match event.code {
                KeyCode::Right => app.on_right(),
                KeyCode::Left => app.on_left(),
                KeyCode::Up => app.on_up(),
                KeyCode::Down => app.on_down(),
                KeyCode::Char(character) => app.on_key(character),
                _ => {}
            }
        }
    });

    terminal.draw_web(move |frame| {
        let mut app = app_state.borrow_mut();
        let elapsed = app.on_tick();
        ui::draw(elapsed, frame, &mut app);
    });

    Ok(())
}
