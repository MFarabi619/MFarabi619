//! Microtop — full-screen TUI dashboard over SSH.
//!
//! Launched via the `microtop` shell command. Uses ratatui with a custom
//! ANSI backend that writes escape sequences to the SSH channel.

use alloc::string::String as AllocString;
use core::fmt::Write as FmtWrite;

use ratatui::backend::Backend;
use ratatui::buffer::Cell;
use ratatui::layout::{Constraint, Direction, Layout, Position, Size};
use ratatui::style::{Color, Modifier, Style};
use ratatui::widgets::{Block, Borders, Paragraph, Row, Table};
use ratatui::Terminal;

use esp_hal::clock;

use crate::config;
use crate::services::{identity, system};

use embassy_time::Instant;

#[derive(Debug)]
struct AnsiError;

impl core::fmt::Display for AnsiError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        write!(f, "ANSI backend error")
    }
}

impl core::error::Error for AnsiError {}

/// Ratatui backend that writes ANSI escape sequences to a byte buffer.
struct AnsiBackend {
    buf: AllocString,
    width: u16,
    height: u16,
}

impl AnsiBackend {
    fn new(width: u16, height: u16) -> Self {
        Self {
            buf: AllocString::new(),
            width,
            height,
        }
    }

    fn take_output(&mut self) -> AllocString {
        core::mem::replace(&mut self.buf, AllocString::new())
    }

    fn ansi_fg(&mut self, color: Color) {
        match color {
            Color::Reset => {
                let _ = write!(self.buf, "\x1b[39m");
            }
            Color::Black => {
                let _ = write!(self.buf, "\x1b[30m");
            }
            Color::Red => {
                let _ = write!(self.buf, "\x1b[31m");
            }
            Color::Green => {
                let _ = write!(self.buf, "\x1b[32m");
            }
            Color::Yellow => {
                let _ = write!(self.buf, "\x1b[33m");
            }
            Color::Blue => {
                let _ = write!(self.buf, "\x1b[34m");
            }
            Color::Magenta => {
                let _ = write!(self.buf, "\x1b[35m");
            }
            Color::Cyan => {
                let _ = write!(self.buf, "\x1b[36m");
            }
            Color::White => {
                let _ = write!(self.buf, "\x1b[37m");
            }
            Color::Gray => {
                let _ = write!(self.buf, "\x1b[90m");
            }
            Color::DarkGray => {
                let _ = write!(self.buf, "\x1b[90m");
            }
            Color::LightRed => {
                let _ = write!(self.buf, "\x1b[91m");
            }
            Color::LightGreen => {
                let _ = write!(self.buf, "\x1b[92m");
            }
            Color::LightYellow => {
                let _ = write!(self.buf, "\x1b[93m");
            }
            Color::LightBlue => {
                let _ = write!(self.buf, "\x1b[94m");
            }
            Color::LightMagenta => {
                let _ = write!(self.buf, "\x1b[95m");
            }
            Color::LightCyan => {
                let _ = write!(self.buf, "\x1b[96m");
            }
            Color::Indexed(i) => {
                let _ = write!(self.buf, "\x1b[38;5;{}m", i);
            }
            Color::Rgb(r, g, b) => {
                let _ = write!(self.buf, "\x1b[38;2;{};{};{}m", r, g, b);
            }
        }
    }

    fn ansi_bg(&mut self, color: Color) {
        match color {
            Color::Reset => {
                let _ = write!(self.buf, "\x1b[49m");
            }
            Color::Black => {
                let _ = write!(self.buf, "\x1b[40m");
            }
            Color::Red => {
                let _ = write!(self.buf, "\x1b[41m");
            }
            Color::Green => {
                let _ = write!(self.buf, "\x1b[42m");
            }
            Color::Yellow => {
                let _ = write!(self.buf, "\x1b[43m");
            }
            Color::Blue => {
                let _ = write!(self.buf, "\x1b[44m");
            }
            Color::Magenta => {
                let _ = write!(self.buf, "\x1b[45m");
            }
            Color::Cyan => {
                let _ = write!(self.buf, "\x1b[46m");
            }
            Color::White => {
                let _ = write!(self.buf, "\x1b[47m");
            }
            Color::Gray | Color::DarkGray => {
                let _ = write!(self.buf, "\x1b[100m");
            }
            Color::LightRed => {
                let _ = write!(self.buf, "\x1b[101m");
            }
            Color::LightGreen => {
                let _ = write!(self.buf, "\x1b[102m");
            }
            Color::LightYellow => {
                let _ = write!(self.buf, "\x1b[103m");
            }
            Color::LightBlue => {
                let _ = write!(self.buf, "\x1b[104m");
            }
            Color::LightMagenta => {
                let _ = write!(self.buf, "\x1b[105m");
            }
            Color::LightCyan => {
                let _ = write!(self.buf, "\x1b[106m");
            }
            Color::Indexed(i) => {
                let _ = write!(self.buf, "\x1b[48;5;{}m", i);
            }
            Color::Rgb(r, g, b) => {
                let _ = write!(self.buf, "\x1b[48;2;{};{};{}m", r, g, b);
            }
        }
    }
}

impl Backend for AnsiBackend {
    type Error = AnsiError;

    fn draw<'a, I>(&mut self, content: I) -> Result<(), Self::Error>
    where
        I: Iterator<Item = (u16, u16, &'a Cell)>,
    {
        let mut last_x: u16 = u16::MAX;
        let mut last_y: u16 = u16::MAX;
        let mut last_fg = Color::Reset;
        let mut last_bg = Color::Reset;

        for (x, y, cell) in content {
            if y != last_y || x != last_x + 1 {
                let _ = write!(self.buf, "\x1b[{};{}H", y + 1, x + 1);
            }

            if cell.fg != last_fg {
                self.ansi_fg(cell.fg);
                last_fg = cell.fg;
            }
            if cell.bg != last_bg {
                self.ansi_bg(cell.bg);
                last_bg = cell.bg;
            }

            if cell.modifier.contains(Modifier::BOLD) {
                let _ = write!(self.buf, "\x1b[1m");
            }
            if cell.modifier.contains(Modifier::DIM) {
                let _ = write!(self.buf, "\x1b[2m");
            }

            let _ = write!(self.buf, "{}", cell.symbol());

            if cell.modifier.intersects(Modifier::BOLD | Modifier::DIM) {
                let _ = write!(self.buf, "\x1b[22m");
            }

            last_x = x;
            last_y = y;
        }

        let _ = write!(self.buf, "\x1b[0m");
        Ok(())
    }

    fn hide_cursor(&mut self) -> Result<(), Self::Error> {
        let _ = write!(self.buf, "\x1b[?25l");
        Ok(())
    }

    fn show_cursor(&mut self) -> Result<(), Self::Error> {
        let _ = write!(self.buf, "\x1b[?25h");
        Ok(())
    }

    fn get_cursor_position(&mut self) -> Result<Position, Self::Error> {
        Ok(Position::new(0, 0))
    }

    fn set_cursor_position<P: Into<Position>>(&mut self, pos: P) -> Result<(), Self::Error> {
        let pos = pos.into();
        let _ = write!(self.buf, "\x1b[{};{}H", pos.y + 1, pos.x + 1);
        Ok(())
    }

    fn clear(&mut self) -> Result<(), Self::Error> {
        let _ = write!(self.buf, "\x1b[2J\x1b[H");
        Ok(())
    }

    fn clear_region(
        &mut self,
        _clear_type: ratatui::backend::ClearType,
    ) -> Result<(), Self::Error> {
        let _ = write!(self.buf, "\x1b[2J\x1b[H");
        Ok(())
    }

    fn size(&self) -> Result<Size, Self::Error> {
        Ok(Size::new(self.width, self.height))
    }

    fn window_size(&mut self) -> Result<ratatui::backend::WindowSize, Self::Error> {
        Ok(ratatui::backend::WindowSize {
            columns_rows: Size::new(self.width, self.height),
            pixels: Size::new(0, 0),
        })
    }

    fn flush(&mut self) -> Result<(), Self::Error> {
        Ok(())
    }
}

/// Render one frame of the microtop dashboard and return it as an ANSI string.
pub fn render_frame(width: u16, height: u16) -> AllocString {
    let backend = AnsiBackend::new(width, height);
    let mut terminal = Terminal::new(backend).unwrap();

    let system_snapshot = system::snapshot();
    let sensor_inventory = &system_snapshot.sensors.inventory;
    let carbon_dioxide = system_snapshot.sensors.carbon_dioxide;
    let secs = Instant::now().as_secs();
    let (h, m, s) = (secs / 3600, (secs % 3600) / 60, secs % 60);

    let mut title_str = AllocString::new();
    let _ = write!(
        title_str,
        " {} @ {} | Uptime: {}h {}m {}s ",
        identity::ssh_user(),
        identity::hostname(),
        h,
        m,
        s
    );

    let mut cpu_str = AllocString::new();
    let _ = write!(cpu_str, "Xtensa LX7 @ {} MHz", clock::cpu_clock().as_mhz());
    let mut ip_str = AllocString::new();
    let _ = write!(
        ip_str,
        "{}.{}.{}.{}",
        system_snapshot.network.station.ipv4_address[0],
        system_snapshot.network.station.ipv4_address[1],
        system_snapshot.network.station.ipv4_address[2],
        system_snapshot.network.station.ipv4_address[3]
    );
    let mut ports_str = AllocString::new();
    let _ = write!(
        ports_str,
        "SSH:{} HTTP:{} OTA:{}",
        config::ssh::PORT,
        config::http::PORT,
        config::ota::PORT
    );

    let heap_free = esp_alloc::HEAP.free();
    let mut mem_str = AllocString::new();
    let _ = write!(mem_str, "{} KiB free", heap_free / 1024);

    let mut disk_str = AllocString::new();
    if system_snapshot.storage.sd_card_size_mb > 0 {
        let gb = system_snapshot.storage.sd_card_size_mb as f32 / 1024.0;
        let _ = write!(disk_str, "{:.1} GiB ({})", gb, config::sd_card::FS_TYPE);
    } else {
        let _ = write!(disk_str, "not detected");
    }

    let mut co2_str = AllocString::new();
    let mut temp_str = AllocString::new();
    let mut rh_str = AllocString::new();
    if carbon_dioxide.ok {
        let _ = write!(co2_str, "{:.1} ppm", carbon_dioxide.co2_ppm);
        let _ = write!(temp_str, "{:.1}\u{00b0}C", carbon_dioxide.temperature);
        let _ = write!(rh_str, "{:.1}%", carbon_dioxide.humidity);
    }

    let _ = terminal.draw(|frame| {
        let area = frame.area();

        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(8),
                Constraint::Length(3),
            ])
            .split(area);

        let title_block = Block::default()
            .borders(Borders::ALL)
            .style(Style::default().fg(Color::Cyan));
        frame.render_widget(
            Paragraph::new(title_str.as_str()).block(title_block),
            chunks[0],
        );

        let mid = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
            .split(chunks[1]);

        let sys_block = Block::default()
            .title(" System ")
            .borders(Borders::ALL)
            .style(Style::default().fg(Color::Yellow));

        let sys_rows = [
            Row::new(["Host", "ESP32-S3"]),
            Row::new(["CPU", cpu_str.as_str()]),
            Row::new(["Memory", mem_str.as_str()]),
            Row::new(["Disk", disk_str.as_str()]),
            Row::new(["IP", ip_str.as_str()]),
            Row::new(["Ports", ports_str.as_str()]),
        ];

        let widths = [Constraint::Length(8), Constraint::Min(20)];
        let sys_table = Table::new(sys_rows, widths).block(sys_block);
        frame.render_widget(sys_table, mid[0]);

        let sensor_block = Block::default()
            .title(" Sensors ")
            .borders(Borders::ALL)
            .style(Style::default().fg(Color::Green));

        let mut sensor_rows: heapless::Vec<Row, 8> = heapless::Vec::new();
        if !co2_str.is_empty() {
            let _ = sensor_rows.push(Row::new(["CO2", co2_str.as_str()]));
            let _ = sensor_rows.push(Row::new(["Temp", temp_str.as_str()]));
            let _ = sensor_rows.push(Row::new(["Humidity", rh_str.as_str()]));
        } else {
            let _ = sensor_rows.push(Row::new(["Status", "No readings"]));
        }

        for sensor in sensor_inventory.iter() {
            let _ = sensor_rows.push(Row::new([
                sensor.model,
                sensor.transport_summary().bus_name,
            ]));
        }

        let sensor_table = Table::new(sensor_rows, widths).block(sensor_block);
        frame.render_widget(sensor_table, mid[1]);

        let footer_block = Block::default()
            .borders(Borders::ALL)
            .style(Style::default().fg(Color::DarkGray));
        frame.render_widget(
            Paragraph::new(" Press 'q' to exit microtop")
                .style(Style::default().fg(Color::DarkGray))
                .block(footer_block),
            chunks[2],
        );
    });

    let _ = terminal.hide_cursor();
    terminal.backend_mut().take_output()
}
