use std::io::{self, stdout};
use std::time::Duration;

use crossterm::event::{
    self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind, MouseButton,
    MouseEventKind,
};
use crossterm::execute;

use firmware::ui::{self, Action, FONT_H, FONT_W, TouchState};

fn main() -> io::Result<()> {
    let mut terminal = ratatui::init();
    execute!(stdout(), EnableMouseCapture)?;
    let result = run(&mut terminal);
    execute!(stdout(), DisableMouseCapture)?;
    ratatui::restore();
    result
}

fn run(terminal: &mut ratatui::DefaultTerminal) -> io::Result<()> {
    let mut touch = TouchState::new();

    loop {
        let mut action: Option<Action> = None;
        terminal.draw(|frame| {
            action = ui::render_app(frame, &touch);
        })?;
        touch.commit();

        match action {
            Some(Action::LedOff) => println!("[term] LED OFF tapped"),
            Some(Action::Reboot) => {
                println!("[term] REBOOT tapped — exiting");
                return Ok(());
            }
            None => {}
        }

        if !event::poll(Duration::from_millis(33))? {
            continue;
        }
        match event::read()? {
            Event::Key(key) if key.kind == KeyEventKind::Press => match key.code {
                KeyCode::Char('q') | KeyCode::Esc => return Ok(()),
                _ => {}
            },
            Event::Mouse(mouse) => {
                // Terminal mouse events are cell-based; ui::render_app's hit-test
                // is pixel-based (cell × FONT_W/H), so scale here to keep one
                // hit-test path across all three render targets.
                let px = mouse.column as i32 * FONT_W as i32;
                let py = mouse.row as i32 * FONT_H as i32;
                match mouse.kind {
                    MouseEventKind::Down(MouseButton::Left) => {
                        touch.x = px;
                        touch.y = py;
                        touch.pressed = true;
                    }
                    MouseEventKind::Up(MouseButton::Left) => {
                        touch.pressed = false;
                    }
                    MouseEventKind::Drag(MouseButton::Left) => {
                        touch.x = px;
                        touch.y = py;
                    }
                    _ => {}
                }
            }
            _ => {}
        }
    }
}
