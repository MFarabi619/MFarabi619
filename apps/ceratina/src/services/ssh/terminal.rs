use embassy_futures::select::{select, Either};
use embassy_sync::{blocking_mutex::raw::RawMutex, signal::Signal};
use embedded_io_async::{Read, Write as AsyncWrite};
use heapless::{String, Vec};

use super::history::History;
use super::writer::TerminalWriter;

/// Configuration for the terminal
#[derive(Clone, Copy)]
pub struct TerminalConfig {
    /// Maximum command buffer size
    pub buffer_size: usize,
    /// Prompt string to display
    pub prompt: &'static str,
    /// Enable echo of typed characters
    pub echo: bool,
    /// Enable ANSI escape codes for better terminal control
    pub ansi_enabled: bool,
}

impl Default for TerminalConfig {
    fn default() -> Self {
        Self {
            buffer_size: 128,
            prompt: "> ",
            echo: true,
            ansi_enabled: true,
        }
    }
}

/// Key codes for special keys
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum KeyCode {
    Backspace,
    Delete,
    Enter,
    Tab,
    Escape,
    ArrowUp,
    ArrowDown,
    ArrowLeft,
    ArrowRight,
    CtrlC,
    CtrlD,
    Char(u8),
}

/// Main terminal structure
pub struct Terminal<const BUF_SIZE: usize> {
    config: TerminalConfig,
    buffer: Vec<u8, BUF_SIZE>,
    cursor_pos: usize,
    escape_state: EscapeState,
}

/// State machine for parsing ANSI escape sequences
#[derive(Debug, Clone, Copy, PartialEq)]
enum EscapeState {
    Normal,
    Escape,
    Bracket,
}

impl<const BUF_SIZE: usize> Terminal<BUF_SIZE> {
    /// Create a new terminal instance
    pub fn new(config: TerminalConfig) -> Self {
        Self {
            config,
            buffer: Vec::new(),
            cursor_pos: 0,
            escape_state: EscapeState::Normal,
        }
    }

    /// Get the current buffer as a string slice
    pub fn buffer_str(&self) -> Result<&str, core::str::Utf8Error> {
        core::str::from_utf8(self.buffer.as_slice())
    }

    /// Clear the current buffer
    pub fn clear_buffer(&mut self) {
        self.buffer.clear();
        self.cursor_pos = 0;
    }

    /// Get the current cursor position
    pub fn cursor_position(&self) -> usize {
        self.cursor_pos
    }

    /// Process a single byte of input, handling ANSI escape sequences
    pub fn process_byte(&mut self, byte: u8) -> Option<KeyCode> {
        match self.escape_state {
            EscapeState::Normal => {
                match byte {
                    b'\r' | b'\n' => Some(KeyCode::Enter),
                    0x08 | 0x7F => Some(KeyCode::Backspace),
                    0x03 => Some(KeyCode::CtrlC),
                    0x04 => Some(KeyCode::CtrlD),
                    0x09 => Some(KeyCode::Tab),
                    0x1B => {
                        self.escape_state = EscapeState::Escape;
                        None
                    }
                    byte if byte >= 0x20 && byte < 0x7F => Some(KeyCode::Char(byte)),
                    _ => None,
                }
            }
            EscapeState::Escape => {
                if byte == b'[' {
                    self.escape_state = EscapeState::Bracket;
                    None
                } else {
                    self.escape_state = EscapeState::Normal;
                    Some(KeyCode::Escape)
                }
            }
            EscapeState::Bracket => {
                self.escape_state = EscapeState::Normal;
                match byte {
                    b'A' => Some(KeyCode::ArrowUp),
                    b'B' => Some(KeyCode::ArrowDown),
                    b'C' => Some(KeyCode::ArrowRight),
                    b'D' => Some(KeyCode::ArrowLeft),
                    b'3' => Some(KeyCode::Delete), // Delete sends ESC[3~
                    _ => None,
                }
            }
        }
    }

    /// Handle a key press
    pub fn handle_key(&mut self, key: KeyCode) -> TerminalEvent {
        match key {
            KeyCode::Enter => {
                if self.buffer.is_empty() {
                    TerminalEvent::EmptyCommand
                } else {
                    TerminalEvent::CommandReady
                }
            }
            KeyCode::Backspace => {
                if self.cursor_pos > 0 && !self.buffer.is_empty() {
                    self.buffer.remove(self.cursor_pos - 1);
                    self.cursor_pos -= 1;
                    TerminalEvent::BufferChanged
                } else {
                    TerminalEvent::None
                }
            }
            KeyCode::Delete => {
                if self.cursor_pos < self.buffer.len() {
                    self.buffer.remove(self.cursor_pos);
                    TerminalEvent::BufferChanged
                } else {
                    TerminalEvent::None
                }
            }
            KeyCode::ArrowLeft => {
                if self.cursor_pos > 0 {
                    self.cursor_pos -= 1;
                    TerminalEvent::CursorMoved
                } else {
                    TerminalEvent::None
                }
            }
            KeyCode::ArrowRight => {
                if self.cursor_pos < self.buffer.len() {
                    self.cursor_pos += 1;
                    TerminalEvent::CursorMoved
                } else {
                    TerminalEvent::None
                }
            }
            KeyCode::ArrowUp => TerminalEvent::HistoryPrevious,
            KeyCode::ArrowDown => TerminalEvent::HistoryNext,
            KeyCode::CtrlC => TerminalEvent::Interrupt,
            KeyCode::CtrlD => TerminalEvent::EndOfFile,
            KeyCode::Char(byte) => {
                if self.buffer.len() < BUF_SIZE {
                    // Insert at cursor position
                    if self.cursor_pos == self.buffer.len() {
                        let _ = self.buffer.push(byte);
                    } else {
                        let _ = self.buffer.insert(self.cursor_pos, byte);
                    }
                    self.cursor_pos += 1;
                    TerminalEvent::BufferChanged
                } else {
                    TerminalEvent::BufferFull
                }
            }
            _ => TerminalEvent::None,
        }
    }

    /// Get the current command buffer and clear it
    pub fn take_command(&mut self) -> Result<String<BUF_SIZE>, ()> {
        let result = String::from_utf8(self.buffer.clone()).map_err(|_| ())?;
        self.clear_buffer();
        Ok(result)
    }

    /// Set the buffer content (useful for history navigation)
    pub fn set_buffer(&mut self, content: &str) -> Result<(), ()> {
        self.buffer.clear();
        self.buffer.extend_from_slice(content.as_bytes()).map_err(|_| ())?;
        self.cursor_pos = self.buffer.len();
        Ok(())
    }
}

/// Events that can occur during terminal operation
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum TerminalEvent {
    None,
    BufferChanged,
    CursorMoved,
    CommandReady,
    EmptyCommand,
    BufferFull,
    Interrupt,
    EndOfFile,
    HistoryPrevious,
    HistoryNext,
}

/// Terminal reader task that handles async I/O
pub struct TerminalReader<const BUF_SIZE: usize> {
    terminal: Terminal<BUF_SIZE>,
    history: Option<History<BUF_SIZE>>,
}

impl<const BUF_SIZE: usize> TerminalReader<BUF_SIZE> {
    pub fn new(config: TerminalConfig, history: Option<History<BUF_SIZE>>) -> Self {
        Self {
            terminal: Terminal::new(config),
            history,
        }
    }

    /// Read a complete line from the input
    pub async fn read_line<R, W, M>(
        &mut self,
        reader: &mut R,
        writer: &mut TerminalWriter<'_, W>,
        redraw_signal: Option<&Signal<M, ()>>,
    ) -> Result<String<BUF_SIZE>, ReadLineError>
    where
        R: Read,
        W: AsyncWrite,
        M: RawMutex,
    {
        // Display initial prompt
        let _ = writer.write_prompt(self.terminal.config.prompt).await;

        let mut byte_buf = [0u8; 1];

        loop {
            let event = if let Some(signal) = redraw_signal {
                // Wait for either input or redraw signal
                match select(reader.read(&mut byte_buf), signal.wait()).await {
                    Either::First(Ok(1)) => {
                        if let Some(key) = self.terminal.process_byte(byte_buf[0]) {
                            self.terminal.handle_key(key)
                        } else {
                            TerminalEvent::None
                        }
                    }
                    Either::First(Ok(0)) => TerminalEvent::EndOfFile,
                    Either::First(Err(_)) => return Err(ReadLineError::IoError),
                    Either::Second(_) => {
                        // Redraw requested
                        signal.reset();
                        let _ = writer.clear_line().await;
                        let _ = writer.write_prompt(self.terminal.config.prompt).await;
                        let _ = writer.write_str(self.terminal.buffer_str().unwrap_or("")).await;
                        continue;
                    }
                    _ => continue,
                }
            } else {
                // Simple read without redraw support
                match reader.read(&mut byte_buf).await {
                    Ok(1) => {
                        if let Some(key) = self.terminal.process_byte(byte_buf[0]) {
                            self.terminal.handle_key(key)
                        } else {
                            TerminalEvent::None
                        }
                    }
                    Ok(0) => TerminalEvent::EndOfFile,
                    Err(_) => return Err(ReadLineError::IoError),
                    _ => continue,
                }
            };

            match event {
                TerminalEvent::CommandReady => {
                    let _ = writer.write_str("\r\n").await;
                    let command = self.terminal.take_command()?;
                    
                    // Add to history if available
                    if let Some(ref mut hist) = self.history {
                        let _ = hist.add(&command);
                    }
                    
                    return Ok(command);
                }
                TerminalEvent::EmptyCommand => {
                    let _ = writer.write_str("\r\n").await;
                    let _ = writer.write_prompt(self.terminal.config.prompt).await;
                }
                TerminalEvent::BufferChanged => {
                    if self.terminal.config.echo {
                        // Redraw the line
                        let _ = writer.clear_line().await;
                        let _ = writer.write_prompt(self.terminal.config.prompt).await;
                        let _ = writer.write_str(self.terminal.buffer_str().unwrap_or("")).await;
                    }
                }
                TerminalEvent::Interrupt => {
                    self.terminal.clear_buffer();
                    let _ = writer.write_str("^C\r\n").await;
                    let _ = writer.write_prompt(self.terminal.config.prompt).await;
                }
                TerminalEvent::EndOfFile => {
                    return Err(ReadLineError::EndOfFile);
                }
                TerminalEvent::HistoryPrevious => {
                    if let Some(ref mut hist) = self.history {
                        if let Some(entry) = hist.previous() {
                            let _ = self.terminal.set_buffer(entry);
                            // Redraw the line
                            let _ = writer.clear_line().await;
                            let _ = writer.write_prompt(self.terminal.config.prompt).await;
                            let _ = writer.write_str(self.terminal.buffer_str().unwrap_or("")).await;
                        }
                    }
                }
                TerminalEvent::HistoryNext => {
                    if let Some(ref mut hist) = self.history {
                        if let Some(entry) = hist.next() {
                            let _ = self.terminal.set_buffer(entry);
                        } else {
                            // At the end of history, clear buffer
                            self.terminal.clear_buffer();
                        }
                        // Redraw the line
                        let _ = writer.clear_line().await;
                        let _ = writer.write_prompt(self.terminal.config.prompt).await;
                        let _ = writer.write_str(self.terminal.buffer_str().unwrap_or("")).await;
                    }
                }
                TerminalEvent::BufferFull => {
                    // Optionally signal buffer full (beep?)
                }
                _ => {}
            }
        }
    }
}

/// Errors that can occur while reading a line
#[derive(Debug, Clone, Copy)]
pub enum ReadLineError {
    IoError,
    Utf8Error,
    EndOfFile,
}

impl From<()> for ReadLineError {
    fn from(_: ()) -> Self {
        ReadLineError::Utf8Error
    }
}
