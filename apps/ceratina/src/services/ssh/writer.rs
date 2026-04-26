use core::fmt;
use embedded_io_async::Write as AsyncWrite;

/// Terminal writer for formatted output with ANSI support
pub struct TerminalWriter<'a, W: AsyncWrite> {
    writer: &'a mut W,
    ansi_enabled: bool,
}

impl<'a, W: AsyncWrite> TerminalWriter<'a, W> {
    /// Create a new terminal writer
    pub fn new(writer: &'a mut W, ansi_enabled: bool) -> Self {
        Self {
            writer,
            ansi_enabled,
        }
    }

    /// Write a string
    pub async fn write_str(&mut self, s: &str) -> Result<(), W::Error> {
        self.writer.write_all(s.as_bytes()).await?;
        self.writer.flush().await
    }

    /// Write a formatted string
    pub async fn write_fmt(
        &mut self,
        args: fmt::Arguments<'_>,
    ) -> Result<(), W::Error> {
        // For no_std, we need to format to a temporary buffer
        use heapless::String;
        let mut buffer = String::<256>::new();
        let _ = fmt::write(&mut buffer, args);
        self.write_str(&buffer).await
    }

    /// Write a line (adds \r\n)
    pub async fn writeln(&mut self, s: &str) -> Result<(), W::Error> {
        self.write_str(s).await?;
        self.write_str("\r\n").await
    }

    /// Write the prompt
    pub async fn write_prompt(&mut self, prompt: &str) -> Result<(), W::Error> {
        self.write_str(prompt).await
    }

    /// Clear the current line
    pub async fn clear_line(&mut self) -> Result<(), W::Error> {
        if self.ansi_enabled {
            // Move to start of line and clear
            self.write_str("\r\x1b[K").await
        } else {
            // Just carriage return for simple terminals
            self.write_str("\r").await
        }
    }

    /// Clear the screen
    pub async fn clear_screen(&mut self) -> Result<(), W::Error> {
        if self.ansi_enabled {
            self.write_str("\x1b[2J\x1b[H").await
        } else {
            // Send multiple newlines as fallback
            self.write_str("\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n").await
        }
    }

    /// Move cursor up by n lines
    pub async fn cursor_up(&mut self, n: usize) -> Result<(), W::Error> {
        if self.ansi_enabled && n > 0 {
            use heapless::String;
            let mut cmd = String::<16>::new();
            use core::fmt::Write;
            write!(&mut cmd, "\x1b[{}A", n).ok();
            self.write_str(&cmd).await
        } else {
            Ok(())
        }
    }

    /// Move cursor down by n lines
    pub async fn cursor_down(&mut self, n: usize) -> Result<(), W::Error> {
        if self.ansi_enabled && n > 0 {
            use heapless::String;
            let mut cmd = String::<16>::new();
            use core::fmt::Write;
            write!(&mut cmd, "\x1b[{}B", n).ok();
            self.write_str(&cmd).await
        } else {
            Ok(())
        }
    }

    /// Set text color (ANSI colors: 0-7 for basic colors, 8-15 for bright colors)
    pub async fn set_color(&mut self, color: u8) -> Result<(), W::Error> {
        if self.ansi_enabled {
            use heapless::String;
            let mut cmd = String::<16>::new();
            use core::fmt::Write;
            if color < 8 {
                write!(&mut cmd, "\x1b[3{}m", color).ok();
            } else {
                write!(&mut cmd, "\x1b[9{}m", color - 8).ok();
            }
            self.write_str(&cmd).await
        } else {
            Ok(())
        }
    }

    /// Reset text formatting
    pub async fn reset_format(&mut self) -> Result<(), W::Error> {
        if self.ansi_enabled {
            self.write_str("\x1b[0m").await
        } else {
            Ok(())
        }
    }

    /// Set bold text
    pub async fn set_bold(&mut self, enable: bool) -> Result<(), W::Error> {
        if self.ansi_enabled {
            if enable {
                self.write_str("\x1b[1m").await
            } else {
                self.write_str("\x1b[22m").await
            }
        } else {
            Ok(())
        }
    }

    /// Write colored text
    pub async fn write_colored(
        &mut self,
        text: &str,
        color: u8,
    ) -> Result<(), W::Error> {
        self.set_color(color).await?;
        self.write_str(text).await?;
        self.reset_format().await
    }

    /// Write an error message
    pub async fn write_error(&mut self, msg: &str) -> Result<(), W::Error> {
        if self.ansi_enabled {
            self.write_colored(msg, 1).await // Red
        } else {
            self.writeln(msg).await
        }
    }

    /// Write a success message
    pub async fn write_success(&mut self, msg: &str) -> Result<(), W::Error> {
        if self.ansi_enabled {
            self.write_colored(msg, 2).await // Green
        } else {
            self.writeln(msg).await
        }
    }

    /// Write a warning message
    pub async fn write_warning(&mut self, msg: &str) -> Result<(), W::Error> {
        if self.ansi_enabled {
            self.write_colored(msg, 3).await // Yellow
        } else {
            self.writeln(msg).await
        }
    }

    /// Write an info message
    pub async fn write_info(&mut self, msg: &str) -> Result<(), W::Error> {
        if self.ansi_enabled {
            self.write_colored(msg, 6).await // Cyan
        } else {
            self.writeln(msg).await
        }
    }

    /// Flush the writer
    pub async fn flush(&mut self) -> Result<(), W::Error> {
        self.writer.flush().await
    }
}

/// ANSI color codes for convenience
pub mod colors {
    pub const BLACK: u8 = 0;
    pub const RED: u8 = 1;
    pub const GREEN: u8 = 2;
    pub const YELLOW: u8 = 3;
    pub const BLUE: u8 = 4;
    pub const MAGENTA: u8 = 5;
    pub const CYAN: u8 = 6;
    pub const WHITE: u8 = 7;
    
    pub const BRIGHT_BLACK: u8 = 8;
    pub const BRIGHT_RED: u8 = 9;
    pub const BRIGHT_GREEN: u8 = 10;
    pub const BRIGHT_YELLOW: u8 = 11;
    pub const BRIGHT_BLUE: u8 = 12;
    pub const BRIGHT_MAGENTA: u8 = 13;
    pub const BRIGHT_CYAN: u8 = 14;
    pub const BRIGHT_WHITE: u8 = 15;
}