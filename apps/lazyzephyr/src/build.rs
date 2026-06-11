use std::{
    io::{Read, Write},
    sync::{Arc, Mutex},
    thread,
};

use anyhow::Result;
use portable_pty::{CommandBuilder, PtySize, native_pty_system};
use ratatui::{
    Frame,
    layout::{Constraint, Rect},
    style::{Style, Stylize},
    text::{Line, Span},
    widgets::{Cell, Paragraph, Row, Scrollbar, ScrollbarOrientation, ScrollbarState, Table, TableState, Wrap},
};

use lazyzephyr_core::{
    build::{BuildAction, BuildRunner, BuildStatus},
    input::Key,
    theme::Theme,
};

const SCROLLBACK_LEN: usize = 5000;

enum Kind {
    Pty,
    Table {
        headers:  &'static [&'static str],
        group_by: Option<usize>,
    },
}

struct CommandSpec {
    command: &'static str,
    args:    &'static [&'static str],
    kind:    Kind,
}

struct ActionSpec {
    action:   BuildAction,
    commands: &'static [CommandSpec],
}

const LIST_TABS:      &[&str] = &["Project", "SDK", "Boards"];
const LIST_HEADERS:   &[&str] = &["NAME", "PATH", "REVISION", "URL"];
const BOARDS_HEADERS: &[&str] = &["NAME", "FULL NAME", "VENDOR"];

const ACTIONS: &[ActionSpec] = &[
    ActionSpec {
        action: BuildAction { name: "menuconfig", icon: "\u{f0493}", tabs: &[] },
        commands: &[
            CommandSpec {
                command: "west",
                args:    &["build", "-p", "never", "-t", "menuconfig"],
                kind:    Kind::Pty,
            },
        ],
    },
    ActionSpec {
        action: BuildAction { name: "list", icon: "\u{f00b}", tabs: LIST_TABS },
        commands: &[
            CommandSpec {
                command: "west",
                args:    &["list", "-f", "{name}\t{path}\t{revision}\t{url}"],
                kind:    Kind::Table { headers: LIST_HEADERS, group_by: None },
            },
            CommandSpec {
                command: "west",
                args:    &["sdk", "list"],
                kind:    Kind::Pty,
            },
            CommandSpec {
                command: "west",
                args:    &["boards", "-f", "{name}\t{full_name}\t{vendor}"],
                kind:    Kind::Table { headers: BOARDS_HEADERS, group_by: Some(2) },
            },
        ],
    },
    ActionSpec {
        action: BuildAction { name: "snippets", icon: "\u{f022e}", tabs: &[] },
        commands: &[
            CommandSpec {
                command: "west",
                args:    &["snippets"],
                kind:    Kind::Pty,
            },
        ],
    },
];

enum Session {
    Pty(PtySession),
    Text(TextCapture),
}

impl Session {
    fn status(&self) -> BuildStatus {
        match self {
            Session::Pty(p)  => p.status(),
            Session::Text(t) => t.status(),
        }
    }
    fn send_key(&mut self, key: Key) {
        if let Session::Pty(p) = self {
            p.send_key(key);
        }
    }
    fn scroll(&mut self, lines: isize) {
        match self {
            Session::Pty(p)  => p.scroll(lines),
            Session::Text(t) => t.scroll(lines),
        }
    }
    fn render(&mut self, frame: &mut Frame, area: Rect, theme: &Theme) {
        match self {
            Session::Pty(p)  => p.render(frame, area, theme),
            Session::Text(t) => t.render(frame, area, theme),
        }
    }
}

pub struct WestBuildRunner {
    cached_actions: Vec<BuildAction>,
    sessions:       Vec<Vec<Option<Session>>>,
}

impl WestBuildRunner {
    pub fn new() -> Self {
        Self {
            cached_actions: ACTIONS.iter().map(|s| s.action.clone()).collect(),
            sessions:       ACTIONS.iter()
                .map(|s| s.commands.iter().map(|_| None).collect())
                .collect(),
        }
    }

    fn slot_mut(&mut self, action_idx: usize, tab_idx: usize) -> Option<&mut Option<Session>> {
        self.sessions.get_mut(action_idx)?.get_mut(tab_idx)
    }
}

impl BuildRunner for WestBuildRunner {
    fn actions(&self) -> &[BuildAction] {
        &self.cached_actions
    }

    fn status(&self, action_idx: usize, tab_idx: usize) -> BuildStatus {
        self.sessions.get(action_idx)
            .and_then(|v| v.get(tab_idx))
            .and_then(|s| s.as_ref())
            .map(|s| s.status())
            .unwrap_or(BuildStatus::Idle)
    }

    fn poll(&mut self) {}

    fn ensure_spawned(&mut self, action_idx: usize, tab_idx: usize) -> Option<String> {
        let slot = self.slot_mut(action_idx, tab_idx)?;
        if slot.is_some() {
            return None;
        }
        let spec = ACTIONS.get(action_idx)?;
        let cmd  = spec.commands.get(tab_idx)?;
        match &cmd.kind {
            Kind::Pty => match PtySession::spawn(cmd.command, cmd.args) {
                Ok(session) => {
                    *slot = Some(Session::Pty(session));
                    Some(format!("{} {}", cmd.command, cmd.args.join(" ")))
                }
                Err(error) => {
                    eprintln!(
                        "lazyzephyr: failed to spawn `{} {}`: {error}",
                        cmd.command, cmd.args.join(" ")
                    );
                    None
                }
            },
            Kind::Table { headers, group_by } => {
                let capture = TextCapture::spawn(cmd.command, cmd.args, headers, *group_by);
                *slot = Some(Session::Text(capture));
                Some(format!("{} {}", cmd.command, cmd.args.join(" ")))
            }
        }
    }

    fn send_key(&mut self, action_idx: usize, tab_idx: usize, key: Key) {
        if let Some(Some(s)) = self.slot_mut(action_idx, tab_idx) {
            s.send_key(key);
        }
    }

    fn scroll(&mut self, action_idx: usize, tab_idx: usize, lines: isize) {
        if let Some(Some(s)) = self.slot_mut(action_idx, tab_idx) {
            s.scroll(lines);
        }
    }

    fn render(&mut self, action_idx: usize, tab_idx: usize, frame: &mut Frame, area: Rect, theme: &Theme) {
        if let Some(Some(s)) = self.slot_mut(action_idx, tab_idx) {
            s.render(frame, area, theme);
        } else {
            frame.render_widget(
                Paragraph::new(Line::from(
                    Span::raw("press 0 to start").fg(theme.label).bold(),
                )),
                area,
            );
        }
    }

    fn refresh(&mut self, action_idx: usize, tab_idx: usize) {
        if let Some(slot) = self.slot_mut(action_idx, tab_idx) {
            *slot = None;
        }
    }
}

struct TextCapture {
    rows:          Arc<Mutex<Vec<Vec<String>>>>,
    status:        Arc<Mutex<BuildStatus>>,
    error:         Arc<Mutex<Option<String>>>,
    headers:       &'static [&'static str],
    group_by:      Option<usize>,
    scroll_offset: usize,
}

const MAX_COL_WIDTH: usize = 40;

impl TextCapture {
    fn spawn(
        command:  &str,
        args:     &[&str],
        headers:  &'static [&'static str],
        group_by: Option<usize>,
    ) -> Self {
        let rows   = Arc::new(Mutex::new(Vec::<Vec<String>>::new()));
        let status = Arc::new(Mutex::new(BuildStatus::Running));
        let error  = Arc::new(Mutex::new(None));

        let cmd_s = command.to_string();
        let args_v: Vec<String> = args.iter().map(|s| s.to_string()).collect();
        let rows_t   = Arc::clone(&rows);
        let status_t = Arc::clone(&status);
        let error_t  = Arc::clone(&error);

        thread::spawn(move || {
            let outcome = std::process::Command::new(&cmd_s)
                .args(&args_v)
                .output();
            match outcome {
                Ok(output) => {
                    if output.status.success() {
                        let text = String::from_utf8_lossy(&output.stdout);
                        let parsed: Vec<Vec<String>> = text.lines()
                            .filter(|l| !l.trim().is_empty())
                            .map(|l| l.split('\t').map(|s| s.trim().to_string()).collect())
                            .collect();
                        if let Ok(mut r) = rows_t.lock() { *r = parsed; }
                    } else {
                        let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
                        if let Ok(mut e) = error_t.lock() { *e = Some(stderr); }
                    }
                }
                Err(err) => {
                    if let Ok(mut e) = error_t.lock() { *e = Some(format!("{err}")); }
                }
            }
            if let Ok(mut s) = status_t.lock() { *s = BuildStatus::Exited; }
        });

        Self { rows, status, error, headers, group_by, scroll_offset: 0 }
    }

    fn status(&self) -> BuildStatus {
        self.status.lock().map(|g| *g).unwrap_or(BuildStatus::Exited)
    }

    fn scroll(&mut self, lines: isize) {
        if lines > 0 {
            self.scroll_offset = self.scroll_offset.saturating_sub(lines.unsigned_abs() as usize);
        } else {
            self.scroll_offset = self.scroll_offset.saturating_add(lines.unsigned_abs() as usize);
        }
    }

    fn render(&mut self, frame: &mut Frame, area: Rect, theme: &Theme) {
        if let Some(err) = self.error.lock().ok().and_then(|g| g.clone()) {
            frame.render_widget(
                Paragraph::new(Span::raw(err).fg(theme.error)).wrap(Wrap { trim: false }),
                area,
            );
            return;
        }

        let snapshot: Vec<Vec<String>> = self.rows.lock()
            .map(|g| g.clone()).unwrap_or_default();

        if snapshot.is_empty() {
            let message = if self.status() == BuildStatus::Running { "running…" } else { "no rows" };
            frame.render_widget(Paragraph::new(Span::raw(message).fg(theme.label)), area);
            return;
        }

        let body_area = Rect {
            x: area.x,
            y: area.y,
            width: area.width.saturating_sub(1),
            height: area.height,
        };

        let (table, total_rows) = if let Some(group_col) = self.group_by {
            build_grouped_table(theme, &snapshot, self.headers, group_col)
        } else {
            build_flat_table(theme, &snapshot, self.headers)
        };

        let max_scroll = total_rows.saturating_sub(body_area.height.saturating_sub(1) as usize);
        if self.scroll_offset > max_scroll {
            self.scroll_offset = max_scroll;
        }
        let mut state = TableState::default();
        *state.offset_mut() = self.scroll_offset;
        frame.render_stateful_widget(table, body_area, &mut state);

        let mut sb_state = ScrollbarState::new(total_rows.max(1))
            .position(self.scroll_offset)
            .viewport_content_length(body_area.height.saturating_sub(1) as usize);
        let scrollbar = Scrollbar::new(ScrollbarOrientation::VerticalRight)
            .style(Style::new().fg(theme.border));
        frame.render_stateful_widget(scrollbar, area, &mut sb_state);
    }
}

fn cell_style(theme: &Theme, col: usize, last_col: usize) -> Style {
    if col == 0 {
        Style::new().fg(theme.value).bold()
    } else if col == last_col && last_col > 0 {
        Style::new().fg(theme.label)
    } else {
        Style::new().fg(theme.foreground)
    }
}

fn compute_constraints(headers: &[&str], rows: &[Vec<String>]) -> Vec<Constraint> {
    let n = headers.len();
    let mut widths: Vec<usize> = headers.iter().map(|h| h.len()).collect();
    for row in rows {
        for (i, field) in row.iter().take(n).enumerate() {
            widths[i] = widths[i].max(field.chars().count()).min(MAX_COL_WIDTH);
        }
    }
    widths.iter().enumerate().map(|(i, w)| {
        if i + 1 == n { Constraint::Min(0) } else { Constraint::Length(*w as u16) }
    }).collect()
}

fn build_flat_table(
    theme:    &Theme,
    snapshot: &[Vec<String>],
    headers:  &'static [&'static str],
) -> (Table<'static>, usize) {
    let constraints = compute_constraints(headers, snapshot);
    let last_col = headers.len().saturating_sub(1);
    let header = Row::new(headers.iter().map(|h| Cell::from(h.to_string())))
        .style(Style::new().fg(theme.label).bold());
    let rows: Vec<Row<'static>> = snapshot.iter().map(|row| {
        let cells: Vec<Cell<'static>> = row.iter().enumerate().map(|(i, field)| {
            Cell::from(field.clone()).style(cell_style(theme, i, last_col))
        }).collect();
        Row::new(cells)
    }).collect();
    let count = rows.len();
    let table = Table::new(rows, constraints).header(header).column_spacing(1);
    (table, count)
}

fn build_grouped_table(
    theme:     &Theme,
    snapshot:  &[Vec<String>],
    headers:   &'static [&'static str],
    group_col: usize,
) -> (Table<'static>, usize) {
    let filtered_headers: Vec<&'static str> = headers.iter().enumerate()
        .filter(|(i, _)| *i != group_col).map(|(_, h)| *h).collect();

    let filtered_rows: Vec<Vec<String>> = snapshot.iter().map(|row| {
        row.iter().enumerate()
            .filter(|(i, _)| *i != group_col)
            .map(|(_, s)| s.clone())
            .collect()
    }).collect();

    let constraints = compute_constraints(&filtered_headers, &filtered_rows);
    let last_col = filtered_headers.len().saturating_sub(1);

    let header = Row::new(filtered_headers.iter().map(|h| Cell::from(h.to_string())))
        .style(Style::new().fg(theme.label).bold());

    let mut groups: std::collections::BTreeMap<String, Vec<&Vec<String>>> =
        std::collections::BTreeMap::new();
    for row in snapshot {
        let key = row.get(group_col).cloned().unwrap_or_else(|| "(unknown)".to_string());
        groups.entry(key).or_default().push(row);
    }

    let mut rows: Vec<Row<'static>> = Vec::new();
    for (vendor, vendor_rows) in &groups {
        rows.push(Row::new(vec![
            Cell::from(vendor.clone()).style(Style::new().fg(theme.accent).bold()),
        ]));
        for row in vendor_rows {
            let cells: Vec<Cell<'static>> = row.iter().enumerate()
                .filter(|(i, _)| *i != group_col)
                .enumerate()
                .map(|(out_i, (_, field))| {
                    let value = if out_i == 0 { format!("  {field}") } else { field.clone() };
                    Cell::from(value).style(cell_style(theme, out_i, last_col))
                })
                .collect();
            rows.push(Row::new(cells));
        }
    }

    let count = rows.len();
    let table = Table::new(rows, constraints).header(header).column_spacing(1);
    (table, count)
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
        let pair = pty_system.openpty(PtySize {
            rows: 24,
            cols: 80,
            pixel_width: 0,
            pixel_height: 0,
        })?;
        let mut cmd = CommandBuilder::new(command);
        for arg in args {
            cmd.arg(arg);
        }
        if let Ok(cwd) = std::env::current_dir() {
            cmd.cwd(cwd);
        }
        for (key, value) in std::env::vars_os() {
            cmd.env(key, value);
        }
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
                    Ok(n) => {
                        if let Ok(mut parser) = parser_pump.lock() {
                            parser.process(&buffer[..n]);
                        }
                    }
                    Err(_) => break,
                }
            }
            if let Ok(mut status) = status_pump.lock() {
                *status = BuildStatus::Exited;
            }
        });

        Ok(Self {
            parser,
            status,
            master: pair.master,
            writer,
            _child: child,
            last_rows: 24,
            last_cols: 80,
            scrollback_offset: 0,
        })
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
        let pty_area = Rect {
            x: area.x,
            y: area.y,
            width: area.width.saturating_sub(1),
            height: area.height,
        };

        let rows = pty_area.height.max(1);
        let cols = pty_area.width.max(1);
        if rows != self.last_rows || cols != self.last_cols {
            if let Ok(mut parser) = self.parser.lock() {
                parser.screen_mut().set_size(rows, cols);
            }
            let _ = self.master.resize(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            });
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
        let scrollbar = Scrollbar::new(ScrollbarOrientation::VerticalRight)
            .style(Style::new().fg(theme.border));
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
