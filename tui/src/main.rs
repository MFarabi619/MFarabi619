use std::io;

use ratatui::{
    Frame,
    buffer::Buffer,
    layout::{Constraint, Layout, Rect},
    style::{Color, Style, Stylize},
    symbols::border,
    text::{Line, Span, Text},
    widgets::{Block, BorderType, Paragraph, Widget},
};

#[cfg(not(target_arch = "wasm32"))]
use {
    crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind},
    ratatui::DefaultTerminal,
    reqwest::blocking::Client,
    std::{
        sync::mpsc::{self, Receiver, TryRecvError},
        thread,
        time::{Duration, Instant},
    },
};

#[cfg(target_arch = "wasm32")]
use {
    gloo_net::http::Request,
    ratatui::Terminal,
    ratzilla::{DomBackend, WebRenderer, event::KeyCode},
    std::{cell::RefCell, rc::Rc},
    wasm_bindgen_futures::spawn_local,
    web_time::{Duration, Instant},
};

const FILE_SYSTEM_LIST_ENDPOINT: &str = "http://10.0.0.165/api/filesystem/list";
const FILE_SYSTEM_REFRESH_INTERVAL_SECONDS: u64 = 5;

#[derive(Clone, Debug, serde::Deserialize)]
pub struct FileSystemEntry {
    name: String,
    size: u64,
    #[allow(dead_code)]
    last_write_unix: u64,
}

#[derive(Clone, Debug, Default)]
pub enum FileSystemLoadState {
    #[default]
    Idle,
    Loading,
    Loaded,
    Error(String),
}

#[derive(Debug)]
pub struct App {
    counter: u8,
    exit: bool,
    file_system_entries: Vec<FileSystemEntry>,
    file_system_load_state: FileSystemLoadState,
    last_file_system_refresh: Option<Instant>,
    #[cfg(not(target_arch = "wasm32"))]
    file_system_receiver: Option<Receiver<Result<Vec<FileSystemEntry>, String>>>,
}

impl Default for App {
    fn default() -> Self {
        Self {
            counter: 0,
            exit: false,
            file_system_entries: Vec::new(),
            file_system_load_state: FileSystemLoadState::Idle,
            last_file_system_refresh: None,
            #[cfg(not(target_arch = "wasm32"))]
            file_system_receiver: None,
        }
    }
}

impl App {
    #[cfg(not(target_arch = "wasm32"))]
    pub fn run(&mut self, terminal: &mut DefaultTerminal) -> io::Result<()> {
        self.start_file_system_refresh();

        while !self.exit {
            // self.poll_file_system_refresh();
            self.refresh_file_system_if_due();
            terminal.draw(|frame| self.draw(frame))?;
            self.handle_events()?;
        }

        Ok(())
    }

    fn draw(&self, frame: &mut Frame) {
        frame.render_widget(self, frame.area());
    }

    fn exit(&mut self) {
        self.exit = true;
    }

    fn increment_counter(&mut self) {
        self.counter = self.counter.saturating_add(1);
    }

    fn decrement_counter(&mut self) {
        self.counter = self.counter.saturating_sub(1);
    }

    fn is_file_system_refresh_due(&self) -> bool {
        if matches!(self.file_system_load_state, FileSystemLoadState::Loading) {
            return false;
        }

        self.last_file_system_refresh
            .is_none_or(|last_refresh_time| {
                last_refresh_time.elapsed()
                    >= Duration::from_secs(FILE_SYSTEM_REFRESH_INTERVAL_SECONDS)
            })
    }

    fn apply_file_system_result(&mut self, fetch_result: Result<Vec<FileSystemEntry>, String>) {
        self.last_file_system_refresh = Some(Instant::now());
        match fetch_result {
            Ok(file_system_entries) => {
                self.file_system_entries = file_system_entries;
                self.file_system_load_state = FileSystemLoadState::Loaded;
            }
            Err(fetch_error) => {
                self.file_system_load_state = FileSystemLoadState::Error(fetch_error);
            }
        }
    }

    fn format_file_size(bytes: u64) -> String {
        if bytes < 1024 {
            return format!("{bytes} B");
        }

        let kibibytes = bytes as f64 / 1024.0;
        if kibibytes < 1024.0 {
            return format!("{kibibytes:.1} KB");
        }

        let mebibytes = kibibytes / 1024.0;
        format!("{mebibytes:.2} MB")
    }

    fn split_file_system_entries(&self) -> (Vec<&FileSystemEntry>, Vec<&FileSystemEntry>) {
        let mut sd_entries = Vec::new();
        let mut littlefs_entries = Vec::new();

        for file_system_entry in &self.file_system_entries {
            if file_system_entry.name.starts_with("littlefs/") {
                littlefs_entries.push(file_system_entry);
            } else {
                sd_entries.push(file_system_entry);
            }
        }

        (sd_entries, littlefs_entries)
    }

    fn display_file_name(file_system_entry: &FileSystemEntry, source_prefix: &str) -> String {
        file_system_entry
            .name
            .strip_prefix(source_prefix)
            .unwrap_or(&file_system_entry.name)
            .to_owned()
    }

    fn file_system_section_lines(
        &self,
        source_entries: &[&FileSystemEntry],
        source_prefix: &str,
    ) -> Vec<Line<'static>> {
        let mut lines = Vec::new();

        match &self.file_system_load_state {
            FileSystemLoadState::Idle => lines.push(Line::from("Press R to load files")),
            FileSystemLoadState::Loading => lines.push(Line::from("Loading filesystem...")),
            FileSystemLoadState::Error(fetch_error) => lines.push(Line::from(vec![Span::styled(
                format!("Error: {fetch_error}"),
                Style::default().fg(Color::LightRed),
            )])),
            FileSystemLoadState::Loaded => {
                if source_entries.is_empty() {
                    lines.push(Line::from(vec![Span::styled(
                        "No files found.",
                        Style::default().fg(Color::DarkGray),
                    )]));
                } else {
                    for file_system_entry in source_entries {
                        let file_name = Self::display_file_name(file_system_entry, source_prefix);
                        let file_size = Self::format_file_size(file_system_entry.size);
                        lines.push(Line::from(vec![
                            Span::styled("📄 ", Style::default().fg(Color::LightYellow)),
                            Span::styled(file_name, Style::default().fg(Color::Yellow)),
                            Span::raw("  "),
                            Span::styled(file_size, Style::default().fg(Color::DarkGray)),
                        ]));
                    }
                }
            }
        }

        lines
    }

    #[cfg(not(target_arch = "wasm32"))]
    fn start_file_system_refresh(&mut self) {
        if matches!(self.file_system_load_state, FileSystemLoadState::Loading) {
            return;
        }

        self.file_system_load_state = FileSystemLoadState::Loading;
        let (result_sender, result_receiver) = mpsc::channel();
        self.file_system_receiver = Some(result_receiver);

        thread::spawn(move || {
            let request_result = Client::new()
                .get(FILE_SYSTEM_LIST_ENDPOINT)
                .send()
                .and_then(|response| response.error_for_status())
                .and_then(|response| response.json::<Vec<FileSystemEntry>>())
                .map_err(|error| format!("filesystem request failed: {error}"));

            let _ = result_sender.send(request_result);
        });
    }

    #[cfg(not(target_arch = "wasm32"))]
    fn poll_file_system_refresh(&mut self) {
        let Some(result_receiver) = self.file_system_receiver.take() else {
            return;
        };

        match result_receiver.try_recv() {
            Ok(fetch_result) => self.apply_file_system_result(fetch_result),
            Err(TryRecvError::Empty) => {
                self.file_system_receiver = Some(result_receiver);
            }
            Err(TryRecvError::Disconnected) => {
                self.apply_file_system_result(Err("filesystem worker disconnected".to_owned()));
            }
        }
    }

    #[cfg(not(target_arch = "wasm32"))]
    fn refresh_file_system_if_due(&mut self) {
        if self.is_file_system_refresh_due() {
            self.start_file_system_refresh();
        }
    }

    #[cfg(not(target_arch = "wasm32"))]
    fn handle_key_event(&mut self, key_event: KeyEvent) {
        match key_event.code {
            KeyCode::Char('q') => self.exit(),
            KeyCode::Left => self.decrement_counter(),
            KeyCode::Right => self.increment_counter(),
            KeyCode::Char('r') => self.start_file_system_refresh(),
            _ => {}
        }
    }

    #[cfg(not(target_arch = "wasm32"))]
    fn handle_events(&mut self) -> io::Result<()> {
        if !event::poll(Duration::from_millis(50))? {
            return Ok(());
        }

        if let Event::Key(key_event) = event::read()?
            && key_event.kind == KeyEventKind::Press
        {
            self.handle_key_event(key_event);
        }

        Ok(())
    }

    #[cfg(target_arch = "wasm32")]
    fn start_file_system_refresh_web(application_state: Rc<RefCell<Self>>) {
        {
            let mut application = application_state.borrow_mut();
            if matches!(
                application.file_system_load_state,
                FileSystemLoadState::Loading
            ) {
                return;
            }
            application.file_system_load_state = FileSystemLoadState::Loading;
        }

        spawn_local(async move {
            let fetch_result = Self::fetch_file_system_entries_web().await;
            application_state
                .borrow_mut()
                .apply_file_system_result(fetch_result);
        });
    }

    #[cfg(target_arch = "wasm32")]
    fn maybe_refresh_file_system_web(application_state: &Rc<RefCell<Self>>) {
        let should_refresh = application_state.borrow().is_file_system_refresh_due();
        if should_refresh {
            Self::start_file_system_refresh_web(application_state.clone());
        }
    }

    #[cfg(target_arch = "wasm32")]
    async fn fetch_file_system_entries_web() -> Result<Vec<FileSystemEntry>, String> {
        let response = Request::get(FILE_SYSTEM_LIST_ENDPOINT)
            .send()
            .await
            .map_err(|error| format!("filesystem request failed: {error}"))?;

        if !response.ok() {
            return Err(format!(
                "filesystem request failed with status {}",
                response.status()
            ));
        }

        response
            .json::<Vec<FileSystemEntry>>()
            .await
            .map_err(|error| {
                format!(
                    "filesystem JSON decode failed: {error}. endpoint: {FILE_SYSTEM_LIST_ENDPOINT}"
                )
            })
    }
}

impl Widget for &App {
    fn render(self, area: Rect, buffer: &mut Buffer) {
        let layout = Layout::horizontal([Constraint::Percentage(70), Constraint::Percentage(30)]);
        let [left_area, right_area] = layout.areas(area);

        let left_title = Line::from(" 🟨 Apidae Systems Ceratina 🟨 ".yellow().bold());
        let left_instructions = Line::from(vec![
            " Decrement ".into(),
            "<Left>".light_yellow().bold(),
            " Increment ".into(),
            "<Right>".light_yellow().bold(),
            " Refresh ".into(),
            "<R>".light_yellow().bold(),
            " Quit ".into(),
            "<Q> ".light_yellow().bold(),
        ]);

        let left_block = Block::bordered()
            .border_set(border::THICK)
            .border_style(Color::Yellow)
            .border_type(BorderType::Double)
            .title(left_title.centered())
            .title_bottom(left_instructions.centered());

        let left_text = Text::from(vec![Line::from(vec![
            "Value: ".into(),
            self.counter.to_string().yellow(),
        ])]);

        Paragraph::new(left_text)
            .centered()
            .block(left_block)
            .render(left_area, buffer);

        let right_block = Block::bordered()
            .border_set(border::THICK)
            .border_style(Color::Yellow)
            .border_type(BorderType::Double)
            .title(Line::from(" 📚 Filesystems ").centered());

        let right_inner_area = right_block.inner(right_area);
        right_block.render(right_area, buffer);

        let right_sections = Layout::vertical([
            Constraint::Percentage(52),
            Constraint::Percentage(44),
            Constraint::Percentage(4),
        ])
        .spacing(1)
        .split(right_inner_area);

        let (sd_entries, littlefs_entries) = self.split_file_system_entries();

        let sd_block = Block::bordered()
            .border_style(Color::DarkGray)
            .title(Span::styled(
                "💾 SD Card ",
                Style::default().fg(Color::Yellow).bold(),
            ));
        Paragraph::new(self.file_system_section_lines(&sd_entries, "sd/"))
            .block(sd_block)
            .render(right_sections[0], buffer);

        let littlefs_block = Block::bordered()
            .border_style(Color::DarkGray)
            .title(Span::styled(
                " 🐁 LittleFS ",
                Style::default().fg(Color::Yellow).bold(),
            ));
        Paragraph::new(self.file_system_section_lines(&littlefs_entries, "littlefs/"))
            .block(littlefs_block)
            .render(right_sections[1], buffer);

        let footer = Line::from(vec![
            Span::styled("↻ ", Style::default().fg(Color::DarkGray)),
            Span::styled("Press R to refresh", Style::default().fg(Color::DarkGray)),
        ]);
        Paragraph::new(vec![footer]).render(right_sections[2], buffer);
    }
}

#[cfg(not(target_arch = "wasm32"))]
fn main() -> io::Result<()> {
    let mut terminal = ratatui::init();
    let application_result = App::default().run(&mut terminal);
    ratatui::restore();
    application_result
}

#[cfg(target_arch = "wasm32")]
fn main() -> io::Result<()> {
    let application_state = Rc::new(RefCell::new(App::default()));
    App::start_file_system_refresh_web(application_state.clone());

    let terminal = Terminal::new(DomBackend::new()?)?;

    terminal.on_key_event({
        let application_state = application_state.clone();
        move |event| match event.code {
            KeyCode::Char('q') => application_state.borrow_mut().exit(),
            KeyCode::Left => application_state.borrow_mut().decrement_counter(),
            KeyCode::Right => application_state.borrow_mut().increment_counter(),
            KeyCode::Char('r') => App::start_file_system_refresh_web(application_state.clone()),
            _ => {}
        }
    });

    terminal.draw_web(move |frame| {
        App::maybe_refresh_file_system_web(&application_state);
        application_state.borrow().draw(frame);
    });

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn render_includes_filesystem_panel_title() {
        let application = App::default();
        let mut buffer = Buffer::empty(Rect::new(0, 0, 100, 8));

        application.render(buffer.area, &mut buffer);

        let rendered_text: String = buffer
            .content
            .iter()
            .map(|cell| cell.symbol())
            .collect::<Vec<_>>()
            .join("");

        assert!(rendered_text.contains("Filesystem"));
    }

    #[test]
    fn handle_key_event() -> io::Result<()> {
        let mut application = App::default();

        application.handle_key_event(KeyCode::Right.into());
        assert_eq!(application.counter, 1);

        application.handle_key_event(KeyCode::Left.into());
        assert_eq!(application.counter, 0);

        application.handle_key_event(KeyCode::Left.into());
        assert_eq!(application.counter, 0);

        let mut quit_application = App::default();
        quit_application.handle_key_event(KeyCode::Char('q').into());
        assert!(quit_application.exit);

        Ok(())
    }
}
