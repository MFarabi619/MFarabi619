use lazyzephyr_core::{App, Key, layout};

cfg_if::cfg_if! {
    if #[cfg(not(target_arch = "wasm32"))] {
        mod analyze;
        mod build;
        mod config_io;
        mod elf_inspect;
        mod matcher;
        mod mcumgr;
        mod pinout_image;
        mod probes;
        mod runner;
        mod smp;
        mod waiting;
        mod workspace;

        use crossterm::{
            event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyEventKind, MouseButton, MouseEventKind},
            execute,
        };
        use ratatui::DefaultTerminal;
        use std::{io, time::Duration};

        const FRAME_POLL_INTERVAL_MS: u64 = 100;

        fn key_from_crossterm(event: crossterm::event::KeyEvent) -> Key {
            use crossterm::event::{KeyCode, KeyModifiers};
            let ctrl = event.modifiers.contains(KeyModifiers::CONTROL);
            match event.code {
                KeyCode::Char(character) if ctrl => Key::Ctrl(character),
                KeyCode::Char(character) => Key::Char(character),
                KeyCode::Enter           => Key::Enter,
                KeyCode::Esc             => Key::Esc,
                KeyCode::Tab if event.modifiers.contains(KeyModifiers::SHIFT) => Key::BackTab,
                KeyCode::Tab             => Key::Tab,
                KeyCode::BackTab         => Key::BackTab,
                KeyCode::Up              => Key::Up,
                KeyCode::Down            => Key::Down,
                KeyCode::Left            => Key::Left,
                KeyCode::Right           => Key::Right,
                KeyCode::Backspace       => Key::Backspace,
                _                        => Key::Unknown,
            }
        }

        fn key_from_mouse(event: crossterm::event::MouseEvent) -> Option<Key> {
            match event.kind {
                MouseEventKind::Down(MouseButton::Left) => Some(Key::Click(event.column, event.row)),
                MouseEventKind::ScrollUp                => Some(Key::ScrollUp(event.column, event.row)),
                MouseEventKind::ScrollDown              => Some(Key::ScrollDown(event.column, event.row)),
                _                                       => None,
            }
        }

        fn run_native(app: &mut App, terminal: &mut DefaultTerminal) -> io::Result<()> {
            while !app.should_quit {
                app.advance_frame();
                terminal.draw(|frame| layout(frame, app))?;

                if event::poll(Duration::from_millis(FRAME_POLL_INTERVAL_MS))? {
                    match event::read()? {
                        Event::Key(key_event) if key_event.kind == KeyEventKind::Press => {
                            app.handle_key(key_from_crossterm(key_event));
                        }
                        Event::Mouse(mouse_event) => {
                            if let Some(key) = key_from_mouse(mouse_event) {
                                app.handle_key(key);
                            }
                        }
                        _ => {}
                    }
                }
            }
            Ok(())
        }

        fn build_source() -> Box<dyn lazyzephyr_core::commands::source::Source> {
            match smp::SmpSerialSource::auto() {
                Ok(source) => Box::new(source),
                Err(error) => {
                    eprintln!("lazyzephyr: no SMP-capable device auto-detected ({error}); using mock source");
                    Box::new(lazyzephyr_core::commands::source::mock::MockSource::new())
                }
            }
        }

        fn build_mcumgr(cfg: &lazyzephyr_core::config::McumgrConfig)
            -> std::sync::Arc<dyn lazyzephyr_core::commands::mcumgr::McumgrService>
        {
            use lazyzephyr_core::commands::mcumgr::noop_arc;
            use std::time::Duration;
            if cfg.address.is_empty() { return noop_arc(); }
            let addr = if cfg.address.contains(':') { cfg.address.clone() }
                       else { format!("{}:1337", cfg.address) };
            let parsed: std::net::SocketAddr = match addr.parse() {
                Ok(a) => a,
                Err(err) => {
                    eprintln!("lazyzephyr: invalid mcumgr address {addr:?}: {err}");
                    return noop_arc();
                }
            };
            match mcumgr::UdpMcumgr::connect(parsed, Duration::from_millis(cfg.timeout_ms)) {
                Ok(c) => std::sync::Arc::new(c),
                Err(err) => {
                    eprintln!("lazyzephyr: mcumgr UDP connect to {parsed} failed: {err}");
                    noop_arc()
                }
            }
        }

        fn main() -> io::Result<()> {
            probe_rs_espressif::register_plugin();
            let source  = build_source();
            let builder = Box::new(build::WestBuildRunner::new());
            let probes  = Box::new(probes::ProbeRsRegistry::new());
            let runner  = Box::new(runner::ThreadedRunner);
            let config  = config_io::load();
            let elf     = analyze::load();
            let mouse   = config.gui.mouse_events;
            let matcher: Box<dyn lazyzephyr_core::tui::matcher::Matcher> = if config.gui.fuzzy_search {
                Box::new(matcher::NucleoMatcher::new())
            } else {
                Box::new(lazyzephyr_core::tui::matcher::SubstringMatcher)
            };
            let mcumgr_svc: std::sync::Arc<dyn lazyzephyr_core::commands::mcumgr::McumgrService> =
                build_mcumgr(&config.mcumgr);
            let pinout_img: std::sync::Arc<dyn lazyzephyr_core::tui::pinout_image::PinoutImageRenderer> = {
                let home = std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default()).join("MFarabi619");
                std::sync::Arc::new(pinout_image::PinoutImages::load(vec![
                    ("xiao_esp32s3".into(),   home.join("assets/xiao-esp32s3-pinout-2.png")),
                    ("walter_esp32s3".into(), home.join("assets/walter-iot-pinout.png")),
                ]))
            };
            let workspace = workspace::load();
            let mut app = App::new(source, builder, probes, runner, matcher, mcumgr_svc, pinout_img, config, elf, workspace);
            if mouse { execute!(io::stdout(), EnableMouseCapture)?; }
            let result = ratatui::run(|terminal| run_native(&mut app, terminal));
            if mouse { let _ = execute!(io::stdout(), DisableMouseCapture); }
            result
        }
    } else {
        use ratatui::Terminal;
        use ratzilla::{DomBackend, WebRenderer};
        use std::{cell::RefCell, rc::Rc};

        fn key_from_ratzilla(event: ratzilla::event::KeyEvent) -> Key {
            use ratzilla::event::KeyCode;
            match event.code {
                KeyCode::Char(c) if event.ctrl  => Key::Ctrl(c),
                KeyCode::Char(c)                => Key::Char(c),
                KeyCode::Enter                  => Key::Enter,
                KeyCode::Esc                    => Key::Esc,
                KeyCode::Tab if event.shift     => Key::BackTab,
                KeyCode::Tab                    => Key::Tab,
                KeyCode::Up                     => Key::Up,
                KeyCode::Down                   => Key::Down,
                KeyCode::Left                   => Key::Left,
                KeyCode::Right                  => Key::Right,
                KeyCode::Backspace              => Key::Backspace,
                _                               => Key::Unknown,
            }
        }

        fn key_from_ratzilla_mouse(event: ratzilla::event::MouseEvent) -> Option<Key> {
            use ratzilla::event::{MouseButton, MouseEventKind};
            if event.event != MouseEventKind::Pressed { return None; }
            if event.button != MouseButton::Left { return None; }
            let (cx, cy) = pixel_to_cell(event.x, event.y)?;
            Some(Key::Click(cx, cy))
        }

        fn pixel_to_cell(pixel_x: u32, pixel_y: u32) -> Option<(u16, u16)> {
            use web_sys::window;
            let document = window()?.document()?;
            let sample = document.query_selector("pre span").ok().flatten()?;
            let cell = sample.get_bounding_client_rect();
            if cell.width() < 1.0 || cell.height() < 1.0 { return None; }
            let pre = sample.parent_element()?;
            let grid = pre.parent_element()?;
            let grid_rect = grid.get_bounding_client_rect();
            let col = ((pixel_x as f64 - grid_rect.left()) / cell.width()).max(0.0) as u16;
            let row = ((pixel_y as f64 - grid_rect.top()) / cell.height()).max(0.0) as u16;
            Some((col, row))
        }

        fn main() -> std::io::Result<()> {
            let app_state = Rc::new(RefCell::new(App::with_mock()));

            let terminal = Terminal::new(DomBackend::new()?)?;
            terminal.on_key_event({
                let app_state = app_state.clone();
                move |key_event| {
                    if let Ok(mut app) = app_state.try_borrow_mut() {
                        app.handle_key(key_from_ratzilla(key_event));
                    }
                }
            });
            terminal.on_mouse_event({
                let app_state = app_state.clone();
                move |mouse_event| {
                    if let Some(key) = key_from_ratzilla_mouse(mouse_event) {
                        if let Ok(mut app) = app_state.try_borrow_mut() {
                            app.handle_key(key);
                        }
                    }
                }
            });

            terminal.draw_web(move |frame| {
                let mut app = app_state.borrow_mut();
                app.advance_frame();
                layout(frame, &mut app);
            });

            Ok(())
        }
    }
}
