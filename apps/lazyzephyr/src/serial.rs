use std::{
    io::{Read, Write},
    sync::{Arc, Mutex},
    thread,
};

use anyhow::Result;
use portable_pty::{CommandBuilder, PtySize, native_pty_system};
use ratatui::{
    Frame,
    layout::Rect,
    style::Style,
    widgets::{Scrollbar, ScrollbarOrientation, ScrollbarState},
};

use lazyzephyr_core::{
    commands::serial::{SerialMonitor, SerialStatus},
    theme::Theme,
    tui::input::Key,
};

const SCROLLBACK_LEN: usize = 5000;

pub struct Profile {
    pub device:   String,
    pub baudrate: u32,
    pub command:  String,
    pub args:     Vec<String>,
}

pub struct TtySerial {
    profile: Profile,
    session: Option<PtySession>,
    disabled_status: SerialStatus,
}

impl TtySerial {
    pub fn new(profile: Profile) -> Self {
        Self { profile, session: None, disabled_status: SerialStatus::Disabled }
    }
}

struct PtySession {
    parser:            Arc<Mutex<vt100::Parser>>,
    status:            Arc<Mutex<SerialStatus>>,
    master:            Box<dyn portable_pty::MasterPty + Send>,
    writer:            Box<dyn Write + Send>,
    _child:            Box<dyn portable_pty::Child + Send + Sync>,
    last_rows:         u16,
    last_cols:         u16,
    scrollback_offset: usize,
}

impl PtySession {
    fn spawn(profile: &Profile) -> Result<Self> {
        let pty_system = native_pty_system();
        let pair = pty_system.openpty(PtySize {
            rows: 24, cols: 80, pixel_width: 0, pixel_height: 0,
        })?;
        let mut cmd = CommandBuilder::new(&profile.command);
        for arg in &profile.args {
            cmd.arg(arg);
        }
        if let Ok(cwd) = std::env::current_dir() { cmd.cwd(cwd); }
        for (k, v) in std::env::vars_os() { cmd.env(k, v); }
        let child = pair.slave.spawn_command(cmd)?;
        drop(pair.slave);

        let parser = Arc::new(Mutex::new(vt100::Parser::new(24, 80, SCROLLBACK_LEN)));
        let status = Arc::new(Mutex::new(SerialStatus::Streaming));

        let mut reader = pair.master.try_clone_reader()?;
        let writer = pair.master.take_writer()?;
        let parser_pump = Arc::clone(&parser);
        let status_pump = Arc::clone(&status);
        thread::spawn(move || {
            let mut buffer = [0u8; 4096];
            loop {
                match reader.read(&mut buffer) {
                    Ok(0)  => break,
                    Ok(n)  => {
                        if let Ok(mut parser) = parser_pump.lock() {
                            parser.process(&buffer[..n]);
                        }
                    }
                    Err(_) => break,
                }
            }
            if let Ok(mut status) = status_pump.lock() {
                *status = SerialStatus::Exited;
            }
        });

        Ok(Self {
            parser,
            status,
            master:            pair.master,
            writer,
            _child:            child,
            last_rows:         24,
            last_cols:         80,
            scrollback_offset: 0,
        })
    }
}

fn key_to_bytes(key: Key) -> Option<Vec<u8>> {
    match key {
        Key::Char(c)      => { let mut buf = [0u8; 4]; Some(c.encode_utf8(&mut buf).as_bytes().to_vec()) }
        Key::Ctrl(c)      => {
            let upper = c.to_ascii_uppercase();
            if ('@'..='_').contains(&upper) { Some(vec![(upper as u8) & 0x1f]) }
            else if c == ' ' { Some(vec![0]) }
            else { None }
        }
        Key::Enter        => Some(b"\r".to_vec()),
        Key::Esc          => Some(b"\x1b".to_vec()),
        Key::Tab          => Some(b"\t".to_vec()),
        Key::BackTab      => Some(b"\x1b[Z".to_vec()),
        Key::Up           => Some(b"\x1b[A".to_vec()),
        Key::Down         => Some(b"\x1b[B".to_vec()),
        Key::Right        => Some(b"\x1b[C".to_vec()),
        Key::Left         => Some(b"\x1b[D".to_vec()),
        Key::Backspace    => Some(b"\x7f".to_vec()),
        Key::Click(..) | Key::ScrollUp(..) | Key::ScrollDown(..) | Key::Unknown => None,
    }
}

impl SerialMonitor for TtySerial {
    fn device(&self)  -> &str { &self.profile.device }
    fn baudrate(&self) -> u32 { self.profile.baudrate }
    fn status_line(&self) -> SerialStatus {
        match &self.session {
            Some(s) => s.status.lock().map(|g| *g).unwrap_or(SerialStatus::Exited),
            None    => self.disabled_status,
        }
    }
    fn poll(&mut self) {}

    fn command_preview(&self) -> String {
        let mut s = String::from(&self.profile.command);
        for arg in &self.profile.args {
            s.push(' ');
            s.push_str(arg);
        }
        s
    }

    fn set_device(&mut self, device: String) {
        self.profile.args = vec![device.clone()];
        self.profile.device = device;
    }

    fn start(&mut self) -> Option<String> {
        if self.session.is_some() { return None; }
        match PtySession::spawn(&self.profile) {
            Ok(session) => {
                self.session = Some(session);
                Some(self.command_preview())
            }
            Err(error) => {
                eprintln!("lazyzephyr: failed to spawn serial `{}`: {error}", self.command_preview());
                self.disabled_status = SerialStatus::Exited;
                None
            }
        }
    }

    fn send_key(&mut self, key: Key) {
        let Some(session) = self.session.as_mut() else { return; };
        if let Some(bytes) = key_to_bytes(key) {
            let _ = session.writer.write_all(&bytes);
            let _ = session.writer.flush();
        }
    }

    fn scroll(&mut self, lines: isize) {
        let Some(session) = self.session.as_mut() else { return; };
        if lines > 0 {
            session.scrollback_offset = (session.scrollback_offset + lines as usize).min(SCROLLBACK_LEN);
        } else {
            session.scrollback_offset = session.scrollback_offset.saturating_sub((-lines) as usize);
        }
    }

    fn render(&mut self, frame: &mut Frame, area: Rect, theme: &Theme) {
        let Some(session) = self.session.as_mut() else { return; };

        let pty_area = Rect {
            x:      area.x,
            y:      area.y,
            width:  area.width.saturating_sub(1),
            height: area.height,
        };

        let rows = pty_area.height.max(1);
        let cols = pty_area.width.max(1);
        if rows != session.last_rows || cols != session.last_cols {
            if let Ok(mut parser) = session.parser.lock() {
                parser.screen_mut().set_size(rows, cols);
            }
            let _ = session.master.resize(PtySize {
                rows, cols, pixel_width: 0, pixel_height: 0,
            });
            session.last_rows = rows;
            session.last_cols = cols;
        }
        if let Ok(mut parser) = session.parser.lock() {
            parser.screen_mut().set_scrollback(session.scrollback_offset);
            let widget = tui_term::widget::PseudoTerminal::new(parser.screen());
            frame.render_widget(widget, pty_area);
        }

        let mut state = ScrollbarState::new(SCROLLBACK_LEN)
            .position(SCROLLBACK_LEN.saturating_sub(session.scrollback_offset))
            .viewport_content_length(rows as usize);
        let scrollbar = Scrollbar::new(ScrollbarOrientation::VerticalRight)
            .style(Style::new().fg(theme.border));
        frame.render_stateful_widget(scrollbar, area, &mut state);
    }
}
