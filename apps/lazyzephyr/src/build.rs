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
    style::{Style, Stylize},
    text::Line,
    widgets::{Paragraph, Scrollbar, ScrollbarOrientation, ScrollbarState},
};

use lazyzephyr_core::{
    commands::build::{BuildAction, BuildRunner, BuildStatus},
    theme::Theme,
    tui::input::Key,
};

const SCROLLBACK_LEN: usize = 5000;

const ACTIONS: &[(BuildAction, &str, &[&str])] = &[
    (BuildAction { name: "menuconfig", icon: "\u{f0493}", tabs: &[] }, "west", &["build", "-p", "never", "-t", "menuconfig"]),
];

pub struct WestBuildRunner {
    cached_actions: Vec<BuildAction>,
    sessions:       Vec<Option<PtySession>>,
}

impl WestBuildRunner {
    pub fn new() -> Self {
        Self {
            cached_actions: ACTIONS.iter().map(|(a, ..)| a.clone()).collect(),
            sessions:       ACTIONS.iter().map(|_| None).collect(),
        }
    }
}

impl BuildRunner for WestBuildRunner {
    fn actions(&self) -> &[BuildAction] {
        &self.cached_actions
    }

    fn status(&self, action_idx: usize, _tab_idx: usize) -> BuildStatus {
        self.sessions.get(action_idx)
            .and_then(|s| s.as_ref())
            .map(|s| s.status())
            .unwrap_or(BuildStatus::Idle)
    }

    fn poll(&mut self) {}

    fn ensure_spawned(&mut self, action_idx: usize, _tab_idx: usize) -> Option<String> {
        let slot = self.sessions.get_mut(action_idx)?;
        if slot.is_some() { return None; }
        let (_, command, args) = ACTIONS.get(action_idx)?;
        match PtySession::spawn(command, args) {
            Ok(session) => {
                *slot = Some(session);
                Some(format!("{} {}", command, args.join(" ")))
            }
            Err(error) => {
                eprintln!("lazyzephyr: failed to spawn `{} {}`: {error}", command, args.join(" "));
                None
            }
        }
    }

    fn send_key(&mut self, action_idx: usize, _tab_idx: usize, key: Key) {
        if let Some(Some(s)) = self.sessions.get_mut(action_idx) {
            s.send_key(key);
        }
    }

    fn scroll(&mut self, action_idx: usize, _tab_idx: usize, lines: isize) {
        if let Some(Some(s)) = self.sessions.get_mut(action_idx) {
            s.scroll(lines);
        }
    }

    fn render(&mut self, action_idx: usize, _tab_idx: usize, frame: &mut Frame, area: Rect, theme: &Theme) {
        if let Some(Some(s)) = self.sessions.get_mut(action_idx) {
            s.render(frame, area, theme);
        } else {
            frame.render_widget(
                Paragraph::new(Line::from("press 0 to start".fg(theme.label).bold())),
                area,
            );
        }
    }

    fn refresh(&mut self, action_idx: usize, _tab_idx: usize) {
        if let Some(slot) = self.sessions.get_mut(action_idx) {
            *slot = None;
        }
    }
}

struct PtySession {
    parser: Arc<Mutex<vt100::Parser>>,
    status: Arc<Mutex<BuildStatus>>,
    master: Box<dyn portable_pty::MasterPty + Send>,
    writer: Box<dyn Write + Send>,
    _child: Box<dyn portable_pty::Child + Send + Sync>,
    last_rows: u16,
    last_cols: u16,
    scrollback_offset: usize,
}

impl PtySession {
    fn spawn(command: &str, args: &[&str]) -> Result<Self> {
        let pty_system = native_pty_system();
        let pair = pty_system.openpty(PtySize { rows: 24, cols: 80, pixel_width: 0, pixel_height: 0 })?;
        let mut cmd = CommandBuilder::new(command);
        for arg in args { cmd.arg(arg); }
        if let Ok(cwd) = std::env::current_dir() { cmd.cwd(cwd); }
        for (key, value) in std::env::vars_os() { cmd.env(key, value); }
        let child = pair.slave.spawn_command(cmd)?;
        drop(pair.slave);

        let parser = Arc::new(Mutex::new(vt100::Parser::new(24, 80, SCROLLBACK_LEN)));
        let status = Arc::new(Mutex::new(BuildStatus::Running));

        let mut reader = pair.master.try_clone_reader()?;
        let writer = pair.master.take_writer()?;
        let parser_pump = Arc::clone(&parser);
        let status_pump = Arc::clone(&status);
        thread::spawn(move || {
            let mut buffer = [0u8; 4096];
            loop {
                match reader.read(&mut buffer) {
                    Ok(0) => break,
                    Ok(n) => { if let Ok(mut parser) = parser_pump.lock() { parser.process(&buffer[..n]); } }
                    Err(_) => break,
                }
            }
            if let Ok(mut status) = status_pump.lock() { *status = BuildStatus::Exited; }
        });

        Ok(Self { parser, status, master: pair.master, writer, _child: child, last_rows: 24, last_cols: 80, scrollback_offset: 0 })
    }

    fn status(&self) -> BuildStatus {
        self.status.lock().map(|g| *g).unwrap_or(BuildStatus::Exited)
    }

    fn send_key(&mut self, key: Key) {
        if let Some(bytes) = key_to_bytes(key) {
            let _ = self.writer.write_all(&bytes);
            let _ = self.writer.flush();
        }
    }

    fn scroll(&mut self, lines: isize) {
        if lines > 0 {
            self.scrollback_offset = (self.scrollback_offset + lines as usize).min(SCROLLBACK_LEN);
        } else {
            self.scrollback_offset = self.scrollback_offset.saturating_sub((-lines) as usize);
        }
    }

    fn render(&mut self, frame: &mut Frame, area: Rect, theme: &Theme) {
        let pty_area = Rect { x: area.x, y: area.y, width: area.width.saturating_sub(1), height: area.height };
        let rows = pty_area.height.max(1);
        let cols = pty_area.width.max(1);
        if rows != self.last_rows || cols != self.last_cols {
            if let Ok(mut parser) = self.parser.lock() { parser.screen_mut().set_size(rows, cols); }
            let _ = self.master.resize(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 });
            self.last_rows = rows;
            self.last_cols = cols;
        }
        if let Ok(mut parser) = self.parser.lock() {
            parser.screen_mut().set_scrollback(self.scrollback_offset);
            let widget = tui_term::widget::PseudoTerminal::new(parser.screen());
            frame.render_widget(widget, pty_area);
        }
        let mut state = ScrollbarState::new(SCROLLBACK_LEN)
            .position(SCROLLBACK_LEN.saturating_sub(self.scrollback_offset))
            .viewport_content_length(rows as usize);
        let scrollbar = Scrollbar::new(ScrollbarOrientation::VerticalRight).style(Style::new().fg(theme.border));
        frame.render_stateful_widget(scrollbar, area, &mut state);
    }
}

fn key_to_bytes(key: Key) -> Option<Vec<u8>> {
    match key {
        Key::Char(c)  => { let mut buf = [0u8; 4]; Some(c.encode_utf8(&mut buf).as_bytes().to_vec()) }
        Key::Ctrl(c)  => {
            let upper = c.to_ascii_uppercase();
            if ('@'..='_').contains(&upper) { Some(vec![(upper as u8) & 0x1f]) }
            else if c == ' ' { Some(vec![0]) }
            else { None }
        }
        Key::Enter     => Some(b"\r".to_vec()),
        Key::Esc       => Some(b"\x1b".to_vec()),
        Key::Tab       => Some(b"\t".to_vec()),
        Key::BackTab   => Some(b"\x1b[Z".to_vec()),
        Key::Up        => Some(b"\x1b[A".to_vec()),
        Key::Down      => Some(b"\x1b[B".to_vec()),
        Key::Right     => Some(b"\x1b[C".to_vec()),
        Key::Left      => Some(b"\x1b[D".to_vec()),
        Key::Backspace => Some(b"\x7f".to_vec()),
        Key::Click(..) | Key::ScrollUp(..) | Key::ScrollDown(..) | Key::Unknown => None,
    }
}
