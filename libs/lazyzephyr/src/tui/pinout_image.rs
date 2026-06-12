use alloc::{boxed::Box, sync::Arc};

use ratatui::{Frame, layout::Rect};

pub trait PinoutImageRenderer: Send + Sync {
    fn render(&self, frame: &mut Frame, area: Rect, board: &str);
    fn is_available(&self, board: &str) -> bool;
}

pub struct NoopPinoutImage;

impl PinoutImageRenderer for NoopPinoutImage {
    fn render(&self, _frame: &mut Frame, _area: Rect, _board: &str) {}
    fn is_available(&self, _board: &str) -> bool { false }
}

pub fn noop_arc() -> Arc<dyn PinoutImageRenderer> { Arc::new(NoopPinoutImage) }

#[allow(dead_code)]
pub fn noop_box() -> Box<dyn PinoutImageRenderer> { Box::new(NoopPinoutImage) }
