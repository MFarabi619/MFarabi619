use ratatui::layout::Flex;
use ratatui::prelude::*;

pub fn center(area: Rect, horizontal: Constraint, vertical: Constraint) -> Rect {
    let [area] = Layout::horizontal([horizontal])
        .flex(Flex::Center)
        .areas(area);
    let [area] = Layout::vertical([vertical]).flex(Flex::Center).areas(area);
    area
}

pub struct Delay;

impl Delay {
    pub fn new() -> Self {
        Self
    }

    pub fn delay_millis(&self, ms: u64) {
        std::thread::sleep(std::time::Duration::from_millis(ms));
    }
}
