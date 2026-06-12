use alloc::string::String;
use core::str::FromStr;

use ratatui::style::Color;

const MODIFIERS: &[&str] = &["bold", "reverse", "underline", "strikethrough"];

pub fn parse_color(items: &[String]) -> Option<Color> {
    for item in items {
        let lower = item.to_ascii_lowercase();
        if MODIFIERS.contains(&lower.as_str()) {
            continue;
        }
        if let Ok(color) = Color::from_str(item) {
            return Some(color);
        }
    }
    None
}
