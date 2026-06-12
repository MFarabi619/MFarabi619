use alloc::boxed::Box;

use ratatui::{
    Frame,
    layout::Rect,
    style::Stylize,
    text::Line,
    widgets::Paragraph,
};

use crate::{theme::Theme, tui::input::Key};

pub trait SerialMonitor {
    fn device(&self) -> &str;
    fn baudrate(&self) -> u32;
    fn status_line(&self) -> SerialStatus;
    fn poll(&mut self);
    fn send_key(&mut self, key: Key);
    fn scroll(&mut self, _lines: isize) {}
    fn render(&mut self, frame: &mut Frame, area: Rect, theme: &Theme);
    fn start(&mut self) -> Option<alloc::string::String> { None }
    fn command_preview(&self) -> alloc::string::String { alloc::string::String::new() }
    fn set_device(&mut self, _device: alloc::string::String) {}
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SerialStatus {
    Disabled,
    Connecting,
    Streaming,
    Exited,
}

pub struct NoopSerial;

impl SerialMonitor for NoopSerial {
    fn device(&self) -> &str    { "" }
    fn baudrate(&self) -> u32   { 0 }
    fn status_line(&self) -> SerialStatus { SerialStatus::Disabled }
    fn poll(&mut self) {}
    fn send_key(&mut self, _key: Key) {}
    fn render(&mut self, frame: &mut Frame, area: Rect, theme: &Theme) {
        let para = Paragraph::new(Line::from(
            "serial monitor not configured".fg(theme.label).bold(),
        ));
        frame.render_widget(para, area);
    }
}

pub fn noop_box() -> Box<dyn SerialMonitor> { Box::new(NoopSerial) }
