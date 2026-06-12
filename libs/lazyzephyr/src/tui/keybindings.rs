use alloc::vec::Vec;

use crate::tui::{input::Key, state::App};

#[derive(Debug, Clone)]
pub struct Binding {
    pub keys:              &'static [&'static str],
    pub description:       &'static str,
    pub short_description: Option<&'static str>,
    pub tooltip:           Option<&'static str>,
    pub display_on_screen: bool,
    pub opens_menu:        bool,
    pub tag:               &'static str,
    pub handler:           Option<fn(&mut App)>,
}

impl Binding {
    pub const fn new(keys: &'static [&'static str], description: &'static str) -> Self {
        Self {
            keys,
            description,
            short_description: None,
            tooltip:           None,
            display_on_screen: false,
            opens_menu:        false,
            tag:               "",
            handler:           None,
        }
    }

    pub const fn footer(mut self) -> Self {
        self.display_on_screen = true;
        self
    }

    pub const fn short(mut self, s: &'static str) -> Self {
        self.short_description = Some(s);
        self
    }

    pub const fn tooltip(mut self, s: &'static str) -> Self {
        self.tooltip = Some(s);
        self
    }

    pub const fn tag(mut self, t: &'static str) -> Self {
        self.tag = t;
        self
    }

    pub const fn menu(mut self) -> Self {
        self.opens_menu = true;
        self
    }

    pub const fn handler(mut self, f: fn(&mut App)) -> Self {
        self.handler = Some(f);
        self
    }

    pub fn display_key(&self) -> &'static str {
        self.keys.first().copied().unwrap_or("")
    }

    pub fn label(&self) -> &'static str {
        self.short_description.unwrap_or(self.description)
    }

    pub fn matches(&self, key: Key) -> bool {
        self.keys.iter().any(|spec| key_matches(spec, key))
    }
}

fn key_matches(spec: &str, key: Key) -> bool {
    match key {
        Key::Char(' ') if matches!(spec, "Space" | "space" | "<space>") => true,
        Key::Char(c) => {
            let mut buf = [0u8; 4];
            let s = c.encode_utf8(&mut buf);
            spec == s
        }
        Key::Ctrl(c) => {
            let lower = spec.to_ascii_lowercase();
            (lower.starts_with("ctrl+") || lower.starts_with("c-"))
                && lower.chars().last() == Some(c.to_ascii_lowercase())
        }
        Key::Enter      => matches!(spec, "Enter" | "enter" | "<enter>"),
        Key::Esc        => matches!(spec, "Esc"   | "esc"   | "<esc>"),
        Key::Up         => matches!(spec, "Up"    | "up"    | "↑"),
        Key::Down       => matches!(spec, "Down"  | "down"  | "↓"),
        Key::Left       => matches!(spec, "Left"  | "left"  | "←"),
        Key::Right      => matches!(spec, "Right" | "right" | "→"),
        Key::Tab        => matches!(spec, "Tab"   | "tab"   | "<tab>"),
        Key::BackTab    => matches!(spec, "BackTab" | "backtab" | "Shift+Tab" | "<s-tab>"),
        Key::Backspace  => matches!(spec, "Backspace" | "backspace" | "<bs>"),
        _ => false,
    }
}

pub const NAV_TAG:    &str = "navigation";
pub const ACTION_TAG: &str = "action";
pub const GLOBAL_TAG: &str = "global";

pub fn enter_search(app: &mut App) {
    app.mode = crate::tui::input::InputMode::Search;
    app.current_state_mut().list.filter.clear();
}

pub fn noop(_app: &mut App) {}

pub fn global_bindings() -> Vec<Binding> {
    alloc::vec![
        Binding::new(&["?"],         "show keybindings").footer().short("Keybindings").tag(GLOBAL_TAG),
        Binding::new(&["q"],         "quit").tag(GLOBAL_TAG),
        Binding::new(&["@"],         "open command-log menu").tag(GLOBAL_TAG).menu(),
        Binding::new(&["1", "5"],    "focus pane by number").tag(NAV_TAG),
        Binding::new(&["h", "←"],    "previous panel").tag(NAV_TAG),
        Binding::new(&["l", "→"],    "next panel").tag(NAV_TAG),
        Binding::new(&["j", "↓"],    "move down within panel").tag(NAV_TAG),
        Binding::new(&["k", "↑"],    "move up within panel").tag(NAV_TAG),
        Binding::new(&["g"],         "jump to start of list").tag(NAV_TAG),
        Binding::new(&["G"],         "jump to end of list").tag(NAV_TAG),
        Binding::new(&["0"],         "focus detail pane (press again to cycle tabs)").tag(NAV_TAG),
        Binding::new(&["[", "]"],    "previous / next detail tab").tag(NAV_TAG),
        Binding::new(&["Ctrl+u"],    "scroll detail up").tag(NAV_TAG),
        Binding::new(&["Ctrl+d"],    "scroll detail down").tag(NAV_TAG),
        Binding::new(&["Esc"],       "close popup / leave detail focus").tag(GLOBAL_TAG),
    ]
}
