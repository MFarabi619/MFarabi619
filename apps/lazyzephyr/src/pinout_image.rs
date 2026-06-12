#![allow(dead_code)]

use std::{collections::HashMap, path::PathBuf, sync::Mutex};

use lazyzephyr_core::tui::pinout_image::PinoutImageRenderer;
use ratatui::{Frame, layout::Rect};
use ratatui_image::{Image, Resize, picker::Picker, protocol::Protocol};

pub struct PinoutImages {
    boards: Mutex<HashMap<String, BoardState>>,
}

enum BoardState {
    Ready(Protocol),
    Failed(String),
}

impl PinoutImages {
    pub fn load(entries: Vec<(String, PathBuf)>) -> Self {
        let mut map: HashMap<String, BoardState> = HashMap::new();
        let picker = Picker::from_query_stdio().unwrap_or_else(|_| Picker::halfblocks());
        for (board, path) in entries {
            let result: Result<Protocol, String> = (|| {
                let dyn_img = image::ImageReader::open(&path)
                    .map_err(|e| e.to_string())?
                    .decode()
                    .map_err(|e| e.to_string())?;
                picker
                    .clone()
                    .new_protocol(dyn_img, ratatui::layout::Size::new(80, 24), Resize::Fit(None))
                    .map_err(|e| e.to_string())
            })();
            let state = match result {
                Ok(p)  => BoardState::Ready(p),
                Err(e) => BoardState::Failed(e),
            };
            map.insert(board, state);
        }
        Self { boards: Mutex::new(map) }
    }
}

impl PinoutImageRenderer for PinoutImages {
    fn render(&self, frame: &mut Frame, area: Rect, board: &str) {
        let guard = match self.boards.lock() {
            Ok(g) => g,
            Err(_) => return,
        };
        match guard.get(board) {
            Some(BoardState::Ready(protocol)) => {
                let widget = Image::new(protocol);
                frame.render_widget(widget, area);
            }
            Some(BoardState::Failed(err)) => {
                let p = ratatui::widgets::Paragraph::new(format!("image load failed: {err}"));
                frame.render_widget(p, area);
            }
            None => {
                let p = ratatui::widgets::Paragraph::new(format!("no image registered for board {board:?}"));
                frame.render_widget(p, area);
            }
        }
    }

    fn is_available(&self, board: &str) -> bool {
        self.boards
            .lock()
            .ok()
            .and_then(|g| g.get(board).map(|s| matches!(s, BoardState::Ready(_))))
            .unwrap_or(false)
    }
}
