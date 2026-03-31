use std::io;

mod app;
mod effects;
mod input_router;
mod reducer;
mod selectors;
mod ui;

use app::App;

#[cfg(not(target_arch = "wasm32"))]
use {
    crossterm::{
        event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyEventKind},
        execute,
    },
    ratatui::DefaultTerminal,
    std::time::Duration,
};

#[cfg(target_arch = "wasm32")]
use {
    ratatui::Terminal,
    ratzilla::{DomBackend, WebRenderer},
    std::{cell::RefCell, rc::Rc},
};

#[cfg(not(target_arch = "wasm32"))]
fn run_native(app: &mut App, terminal: &mut DefaultTerminal) -> io::Result<()> {
    app.start_initial_load_native();

    while !app.should_exit() {
        app.poll_native_background_messages();
        app.tick_native();
        terminal.draw(|frame| ui::render(frame, app))?;

        if !event::poll(Duration::from_millis(50))? {
            continue;
        }

        match event::read()? {
            Event::Key(key_event) if key_event.kind == KeyEventKind::Press => {
                let app_key_event = input_router::app_key_event_from_native(key_event);
                if let Some(action) = app_key_event
                    .and_then(|key_event| input_router::map_key_event_to_action(app, key_event))
                {
                    effects::dispatch_native_action(app, action);
                }
            }
            Event::Mouse(mouse_event) => {
                if let Some(action) = input_router::map_native_mouse_event(mouse_event) {
                    effects::dispatch_native_action(app, action);
                }
            }
            _ => {}
        }
    }

    Ok(())
}

#[cfg(not(target_arch = "wasm32"))]
fn main() -> io::Result<()> {
    let mut terminal = ratatui::init();
    let mut app = App::new();

    execute!(io::stdout(), EnableMouseCapture)?;
    let app_result = run_native(&mut app, &mut terminal);

    let mouse_capture_restore_result = execute!(io::stdout(), DisableMouseCapture);
    ratatui::restore();

    mouse_capture_restore_result?;
    app_result
}

#[cfg(target_arch = "wasm32")]
fn main() -> io::Result<()> {
    let app_state = Rc::new(RefCell::new(App::new()));
    App::start_initial_load_web(app_state.clone());

    let terminal = Terminal::new(DomBackend::new()?)?;
    terminal.on_key_event({
        let app_state = app_state.clone();
        move |key_event| {
            let action = {
                let app = app_state.borrow();
                input_router::app_key_event_from_web(key_event).and_then(|app_key_event| {
                    input_router::map_key_event_to_action(&app, app_key_event)
                })
            };

            if let Some(action) = action {
                effects::dispatch_web_action(&app_state, action);
            }
        }
    });

    terminal.on_mouse_event({
        let app_state = app_state.clone();
        move |mouse_event| {
            if let Some(action) = input_router::map_web_mouse_event(mouse_event) {
                effects::dispatch_web_action(&app_state, action);
            }
        }
    });

    terminal.draw_web(move |frame| {
        ui::render(frame, &mut app_state.borrow_mut());
    });

    Ok(())
}
