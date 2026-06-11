use ratatui::widgets::ListState;

#[derive(Debug)]
pub struct ListView {
    pub state: ListState,
}

impl Default for ListView {
    fn default() -> Self { Self::new() }
}

impl ListView {
    pub fn new() -> Self {
        Self { state: ListState::default().with_selected(Some(0)) }
    }

    pub fn step(&mut self, length: usize, direction: isize) {
        if length == 0 { return; }
        let current = self.state.selected().unwrap_or(0) as isize;
        let next    = (current + direction).rem_euclid(length as isize) as usize;
        self.state.select(Some(next));
    }

    pub fn select_first(&mut self) { self.state.select_first(); }
    pub fn select_last(&mut self)  { self.state.select_last(); }
    pub fn selected(&self) -> Option<usize> { self.state.selected() }
}
