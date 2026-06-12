use alloc::{boxed::Box, vec::Vec};

use ratatui::{
    Frame,
    layout::Rect,
    style::Stylize,
    text::Line,
    widgets::Paragraph,
};

use crate::{theme::Theme, tui::input::Key};

#[derive(Debug, Clone)]
pub struct BuildAction {
    pub name: &'static str,
    pub icon: &'static str,
    pub tabs: &'static [&'static str],
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BuildStatus {
    Idle,
    Running,
    Exited,
    Failed,
}

pub trait BuildRunner {
    fn actions(&self) -> &[BuildAction];
    fn status(&self, _action_idx: usize, _tab_idx: usize) -> BuildStatus { BuildStatus::Idle }
    fn poll(&mut self) {}
    fn ensure_spawned(&mut self, _action_idx: usize, _tab_idx: usize) -> Option<alloc::string::String> { None }
    fn send_key(&mut self, _action_idx: usize, _tab_idx: usize, _key: Key) {}
    fn scroll(&mut self, _action_idx: usize, _tab_idx: usize, _lines: isize) {}
    fn render(&mut self, _action_idx: usize, _tab_idx: usize, _frame: &mut Frame, _area: Rect, _theme: &Theme) {}
    fn refresh(&mut self, _action_idx: usize, _tab_idx: usize) {}
}

pub struct NoopBuildRunner;

impl BuildRunner for NoopBuildRunner {
    fn actions(&self) -> &[BuildAction] { &[] }
    fn render(&mut self, _action_idx: usize, _tab_idx: usize, frame: &mut Frame, area: Rect, theme: &Theme) {
        let para = Paragraph::new(Line::from(
            "build runner not configured".fg(theme.label).bold(),
        ));
        frame.render_widget(para, area);
    }
}

pub fn noop_box() -> Box<dyn BuildRunner> { Box::new(NoopBuildRunner) }
