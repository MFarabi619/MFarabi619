mod tabs;

use crate::tabs::{TabsState, draw_tabs};

cfg_if::cfg_if! {
    if #[cfg(not(target_arch = "wasm32"))] {
        use std::io;
        use std::time::Duration;

        use crossterm::event::{self, Event, KeyCode, KeyEventKind};
        use ratatui::DefaultTerminal;

        fn main() -> io::Result<()> {
            let mut terminal = ratatui::init();
            let result = run(&mut terminal);
            ratatui::restore();
            result
        }

        fn run(terminal: &mut DefaultTerminal) -> io::Result<()> {
            let mut tabs = TabsState::new();
            loop {
                terminal.draw(|frame| draw_tabs(frame, &tabs))?;
                if event::poll(Duration::from_millis(33))? {
                    if let Event::Key(key) = event::read()? {
                        if key.kind == KeyEventKind::Press {
                            match key.code {
                                KeyCode::Char('q') | KeyCode::Esc => return Ok(()),
                                KeyCode::Tab | KeyCode::Right => tabs.next(),
                                _ => {}
                            }
                        }
                    }
                }
            }
        }
    } else {
        use std::cell::RefCell;
        use std::rc::Rc;

        use ratzilla::{CanvasBackend, WebRenderer, event::KeyCode, ratatui::Terminal};

        fn main() -> std::io::Result<()> {
            let tabs = Rc::new(RefCell::new(TabsState::new()));

            let backend = CanvasBackend::new()?;
            let mut terminal = Terminal::new(backend)?;

            let _ = terminal.on_key_event({
                let tabs = tabs.clone();
                move |event| {
                    if matches!(event.code, KeyCode::Tab | KeyCode::Right) {
                        tabs.borrow_mut().next();
                    }
                }
            });

            terminal.draw_web({
                let tabs = tabs.clone();
                move |frame| draw_tabs(frame, &tabs.borrow())
            });

            Ok(())
        }
    }
}
