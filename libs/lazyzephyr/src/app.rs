use alloc::{boxed::Box, vec, vec::Vec};

use ratatui::layout::{Position, Rect};

use crate::{
    build::{BuildRunner, noop_box as build_noop_box},
    input::{InputMode, Key},
    panel::{Panel, PanelState, PanelTag},
    probes::{ProbeInfo, ProbeRegistry, noop_box as probes_noop_box},
    serial::{SerialMonitor, noop_box},
    source::{Source, mock::MockSource},
    theme::{THEMES, Theme},
    ui::PANELS,
};

#[derive(Debug, Clone, Copy)]
pub enum AtModalAction { Toggle, Focus, Cancel }

pub struct AtModalOption {
    pub key:    Option<char>,
    pub label:  &'static str,
    pub action: AtModalAction,
}

pub const SCROLL_STEP: isize = 10;

#[derive(Debug, Clone)]
pub struct CommandLogEntry {
    pub action:  alloc::string::String,
    pub command: alloc::string::String,
}

pub const AT_MODAL_OPTIONS: &[AtModalOption] = &[
    AtModalOption { key: Some('t'), label: "Toggle show/hide command log", action: AtModalAction::Toggle },
    AtModalOption { key: Some('f'), label: "Focus command log",             action: AtModalAction::Focus  },
    AtModalOption { key: None,      label: "Cancel",                        action: AtModalAction::Cancel },
];

pub struct App {
    pub mode:                InputMode,
    pub focused_index:       usize,
    pub detail_focused:      bool,
    pub states:              Vec<PanelState>,
    pub panel_rects:         Vec<Rect>,
    pub detail_rect:         Rect,
    pub theme_index:         usize,
    pub frame_tick:          u32,
    pub should_quit:         bool,
    pub help_open:           bool,
    pub command_log_shown:   bool,
    pub command_log_focused: bool,
    pub command_log_rect:    Rect,
    pub command_log_entries: Vec<CommandLogEntry>,
    pub at_modal_open:       bool,
    pub at_modal_selection:  usize,
    pub source:              Box<dyn Source>,
    pub serial:              Box<dyn SerialMonitor>,
    pub build:               Box<dyn BuildRunner>,
    pub probes:              Box<dyn ProbeRegistry>,
    pub probe_list:          Vec<ProbeInfo>,
    pub probe_selection:     usize,
}

impl App {
    pub fn new(
        source: Box<dyn Source>,
        serial: Box<dyn SerialMonitor>,
        build:  Box<dyn BuildRunner>,
        probes: Box<dyn ProbeRegistry>,
    ) -> Self {
        let states = (0..PANELS.len()).map(|_| PanelState::default()).collect();
        let initial = PANELS.iter().position(|p| p.tag() == PanelTag::Threads).unwrap_or(0);
        let mut app = Self {
            mode:                InputMode::Nav,
            focused_index:       initial,
            detail_focused:      false,
            states,
            panel_rects:         vec![Rect::default(); PANELS.len()],
            detail_rect:         Rect::default(),
            theme_index:         0,
            frame_tick:          0,
            should_quit:         false,
            help_open:           false,
            command_log_shown:   true,
            command_log_focused: false,
            command_log_rect:    Rect::default(),
            command_log_entries: Vec::new(),
            at_modal_open:       false,
            at_modal_selection:  0,
            source,
            serial,
            build,
            probes,
            probe_list:          Vec::new(),
            probe_selection:     0,
        };
        app.refresh_probes();
        app
    }

    pub fn with_mock() -> Self {
        Self::new(Box::new(MockSource::new()), noop_box(), build_noop_box(), probes_noop_box())
    }

    pub fn refresh_probes(&mut self) {
        self.probe_list = self.probes.list();
        if self.probe_selection >= self.probe_list.len() {
            self.probe_selection = 0;
        }
    }

    pub fn theme(&self) -> &Theme { &THEMES[self.theme_index] }

    pub fn current_panel(&self) -> &'static dyn Panel { PANELS[self.focused_index] }
    pub fn current_state(&self) -> &PanelState { &self.states[self.focused_index] }
    pub fn current_state_mut(&mut self) -> &mut PanelState { &mut self.states[self.focused_index] }

    pub fn index_of(&self, tag: PanelTag) -> usize {
        PANELS.iter().position(|p| p.tag() == tag).expect("panel tag must be in PANELS")
    }

    pub fn state_of(&self, tag: PanelTag) -> &PanelState {
        &self.states[self.index_of(tag)]
    }

    pub fn state_of_mut(&mut self, tag: PanelTag) -> &mut PanelState {
        let idx = self.index_of(tag);
        &mut self.states[idx]
    }

    fn try_start_serial(&mut self) -> bool {
        use crate::serial::SerialStatus;
        if !self.on_status_serial_popup() { return false; }
        if let Some(probe) = self.probe_list.get(self.probe_selection) {
            if let Some(path) = probe.device_path.clone() {
                self.serial.set_device(path);
            }
        }
        if let Some(cmd) = self.serial.start() {
            self.log_command("Begin Serial Monitor", cmd);
            return true;
        }
        false
    }

    pub fn on_status_serial_popup(&self) -> bool {
        use crate::serial::SerialStatus;
        use crate::ui::status::WestEntry;
        if self.current_panel().tag() != PanelTag::Status { return false; }
        if !self.detail_focused { return false; }
        let entry = crate::ui::StatusPanel.selected_entry(self);
        matches!(entry, WestEntry::Monitor) && self.serial.status_line() == SerialStatus::Disabled
    }

    pub fn log_command(&mut self, action: impl Into<alloc::string::String>, command: impl Into<alloc::string::String>) {
        self.command_log_entries.push(CommandLogEntry {
            action:  action.into(),
            command: command.into(),
        });
        const MAX: usize = 50;
        if self.command_log_entries.len() > MAX {
            let drop = self.command_log_entries.len() - MAX;
            self.command_log_entries.drain(..drop);
        }
    }

    pub fn advance_frame(&mut self) {
        self.frame_tick = self.frame_tick.wrapping_add(1);
        self.source.poll();
        self.serial.poll();
        self.build.poll();
    }

    pub fn handle_key(&mut self, key: Key) {
        if self.at_modal_open {
            self.handle_at_modal_key(key);
            return;
        }
        if self.mode == InputMode::Search {
            self.handle_search_key(key);
            return;
        }
        if matches!(key, Key::Char('@')) {
            self.at_modal_open  = true;
            self.at_modal_selection = 0;
            return;
        }
        if matches!(key, Key::Char('/')) && self.current_panel().supports_filter() {
            self.mode = InputMode::Search;
            self.current_state_mut().filter.clear();
            return;
        }
        if self.command_log_focused && matches!(key, Key::Esc) {
            self.command_log_focused = false;
            return;
        }
        match key {
            Key::Click(x, y) => {
                if let Some(idx) = self.panel_at(x, y) {
                    self.detail_focused = false;
                    self.command_log_focused = false;
                    self.set_focus(idx);
                } else if self.command_log_shown && self.command_log_rect.contains(Position { x, y }) {
                    self.command_log_focused = true;
                    self.detail_focused = false;
                } else if self.detail_rect.contains(Position { x, y }) {
                    self.detail_focused = true;
                    self.command_log_focused = false;
                }
                return;
            }
            Key::ScrollUp(x, y)   => {
                if self.is_serial_at(x, y) {
                    self.serial.scroll(3);
                } else if self.detail_rect.contains(Position { x, y }) {
                    self.current_panel().scroll_detail(self, 3);
                } else if let Some(idx) = self.panel_at(x, y) {
                    let len = PANELS[idx].list_len(self);
                    self.states[idx].list.step(len, -1);
                }
                return;
            }
            Key::ScrollDown(x, y) => {
                if self.is_serial_at(x, y) {
                    self.serial.scroll(-3);
                } else if self.detail_rect.contains(Position { x, y }) {
                    self.current_panel().scroll_detail(self, -3);
                } else if let Some(idx) = self.panel_at(x, y) {
                    let len = PANELS[idx].list_len(self);
                    self.states[idx].list.step(len, 1);
                }
                return;
            }
            _ => {}
        }
        if self.help_open {
            if matches!(key, Key::Char('?') | Key::Esc | Key::Char('q')) {
                self.help_open = false;
            }
            return;
        }
        if self.on_status_serial_popup() {
            match key {
                Key::Up   | Key::Char('k') => {
                    let n = self.probe_list.len();
                    if n > 0 { self.probe_selection = (self.probe_selection + n - 1) % n; }
                    return;
                }
                Key::Down | Key::Char('j') => {
                    let n = self.probe_list.len();
                    if n > 0 { self.probe_selection = (self.probe_selection + 1) % n; }
                    return;
                }
                Key::Char('r') => { self.refresh_probes(); return; }
                _ => {}
            }
        }
        if self.current_panel().tag() == PanelTag::Status && self.detail_focused {
            match key {
                Key::Esc => {
                    self.detail_focused = false;
                    return;
                }
                Key::Char('[') => { self.cycle_detail_tab(-1); return; }
                Key::Enter => {
                    if self.try_start_serial() { return; }
                }
                Key::Char(']') | Key::Char('0') => {
                    self.cycle_detail_tab(1);
                    return;
                }
                Key::Ctrl('u') => { self.current_panel().scroll_detail(self, SCROLL_STEP); return; }
                Key::Ctrl('d') => { self.current_panel().scroll_detail(self, -SCROLL_STEP); return; }
                _ => {}
            }
            use crate::ui::status::WestEntry;
            match crate::ui::StatusPanel.selected_entry(self) {
                WestEntry::Monitor => {
                    self.serial.send_key(key);
                    return;
                }
                WestEntry::Build(action_idx) => {
                    let action = self.build.actions().get(action_idx).cloned();
                    let tab_idx = action.as_ref().map(|a| {
                        if a.tabs.is_empty() { 0 } else {
                            self.current_state().detail_tab.min(a.tabs.len().saturating_sub(1))
                        }
                    }).unwrap_or(0);
                    self.build.send_key(action_idx, tab_idx, key);
                    return;
                }
            }
        }
        if self.current_panel().on_action_key(self, key) {
            return;
        }
        match key {
            Key::Char('q')                              => self.should_quit = true,
            Key::Char('?')                              => self.help_open = true,
            Key::Char('t')                              => {
                self.theme_index = (self.theme_index + 1) % THEMES.len();
            }
            Key::Char('0')                              => {
                self.detail_focused = true;
                self.cycle_detail_tab(1);
            }
            Key::Esc if self.detail_focused             => self.detail_focused = false,
            Key::Char(c) if c.is_ascii_digit() => {
                let index = (c as u8 - b'1') as usize;
                if index < PANELS.len() {
                    if self.focused_index == index {
                        if self.detail_focused {
                            self.detail_focused = false;
                        } else {
                            self.cycle_inner_tab(1);
                        }
                    } else {
                        self.detail_focused = false;
                        self.set_focus(index);
                    }
                }
            }
            Key::Char('h') | Key::Left  | Key::BackTab  => {
                if self.detail_focused { self.detail_focused = false; }
                else { self.cycle_focus(-1); }
            }
            Key::Char('l') | Key::Right | Key::Tab      => {
                if self.detail_focused { self.detail_focused = false; }
                else { self.cycle_focus(1); }
            }
            Key::Char('j') | Key::Down                  => self.move_within_focus(1),
            Key::Char('k') | Key::Up                    => self.move_within_focus(-1),
            Key::Char('g')                              => self.current_state_mut().list.select_first(),
            Key::Char('G')                              => self.current_state_mut().list.select_last(),
            Key::Char('[') | Key::Char('i')             => self.cycle_detail_tab(-1),
            Key::Char(']') | Key::Char('o')             => self.cycle_detail_tab(1),
            Key::Ctrl('u')                              => self.current_panel().scroll_detail(self, SCROLL_STEP),
            Key::Ctrl('d')                              => self.current_panel().scroll_detail(self, -SCROLL_STEP),
            _ => {}
        }
    }

    fn panel_at(&self, x: u16, y: u16) -> Option<usize> {
        self.panel_rects.iter().position(|rect| rect.contains(Position { x, y }))
    }

    fn is_serial_at(&self, x: u16, y: u16) -> bool {
        use crate::ui::status::WestEntry;
        if !self.detail_rect.contains(Position { x, y }) { return false; }
        if self.current_panel().tag() != PanelTag::Status { return false; }
        matches!(crate::ui::StatusPanel.selected_entry(self), WestEntry::Monitor)
    }

    fn handle_search_key(&mut self, key: Key) {
        match key {
            Key::Esc => {
                self.current_state_mut().filter.clear();
                self.current_state_mut().list.select_first();
                self.mode = InputMode::Nav;
            }
            Key::Enter => {
                self.current_state_mut().list.select_first();
                self.mode = InputMode::Nav;
            }
            Key::Backspace => {
                self.current_state_mut().filter.pop();
                self.current_state_mut().list.select_first();
            }
            Key::Char(c) => {
                self.current_state_mut().filter.push(c);
                self.current_state_mut().list.select_first();
            }
            _ => {}
        }
    }

    fn handle_at_modal_key(&mut self, key: Key) {
        let count = AT_MODAL_OPTIONS.len();
        match key {
            Key::Char('t') | Key::Char('T') => self.activate_at_option(AtModalAction::Toggle),
            Key::Char('f') | Key::Char('F') => self.activate_at_option(AtModalAction::Focus),
            Key::Up   | Key::Char('k')      => {
                self.at_modal_selection = (self.at_modal_selection + count - 1) % count;
            }
            Key::Down | Key::Char('j')      => {
                self.at_modal_selection = (self.at_modal_selection + 1) % count;
            }
            Key::Enter => {
                if let Some(action) = AT_MODAL_OPTIONS.get(self.at_modal_selection).map(|o| o.action) {
                    self.activate_at_option(action);
                }
            }
            Key::Esc | Key::Char('@') | Key::Char('q') => self.at_modal_open = false,
            _ => {}
        }
    }

    fn activate_at_option(&mut self, action: AtModalAction) {
        match action {
            AtModalAction::Toggle => self.command_log_shown   = !self.command_log_shown,
            AtModalAction::Focus  => self.command_log_focused = true,
            AtModalAction::Cancel => {}
        }
        self.at_modal_open = false;
    }

    fn set_focus(&mut self, idx: usize) {
        if idx < PANELS.len() && self.focused_index != idx {
            self.focused_index = idx;
            self.states[idx].detail_tab = 0;
            self.command_log_focused = false;
            self.detail_focused = false;
            if PANELS[idx].tag() == PanelTag::Status {
                self.refresh_probes();
            }
            if self.states[idx].list.selected().is_none() {
                self.states[idx].list.select_first();
            }
        }
    }

    fn cycle_focus(&mut self, dir: isize) {
        let n = PANELS.len() as isize;
        let next = ((self.focused_index as isize + dir).rem_euclid(n)) as usize;
        self.set_focus(next);
    }

    fn cycle_detail_tab(&mut self, dir: isize) {
        let count = self.current_panel().detail_tabs(self).len();
        if count <= 1 { return; }
        let current = self.current_state().detail_tab as isize;
        let next = (current + dir).rem_euclid(count as isize) as usize;
        self.current_state_mut().detail_tab = next;
    }

    fn cycle_inner_tab(&mut self, dir: isize) {
        let count = self.current_panel().inner_tabs().len();
        if count <= 1 { return; }
        let state = self.current_state_mut();
        let current = state.list_tab as isize;
        let next = (current + dir).rem_euclid(count as isize) as usize;
        state.list_tab = next;
        state.detail_tab = 0;
        state.list.select_first();
    }

    fn move_within_focus(&mut self, dir: isize) {
        let len = self.current_panel().list_len(self);
        self.current_state_mut().list.step(len, dir);
        let tabs_len = self.current_panel().detail_tabs(self).len();
        if tabs_len > 0 {
            let state = self.current_state_mut();
            if state.detail_tab >= tabs_len { state.detail_tab = 0; }
        }
    }
}
