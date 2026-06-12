use alloc::{boxed::Box, collections::{BTreeSet, VecDeque}, string::String, vec, vec::Vec};

use ratatui::layout::{Position, Rect};

use crate::{
    commands::{
        build::{BuildRunner, noop_box as build_noop_box},
        elf::ElfInfo,
        mcumgr::{McumgrService, noop_arc as mcumgr_noop_arc},
        probes::{ProbeInfo, ProbeRegistry, noop_box as probes_noop_box},
        serial::{SerialMonitor, noop_box},
        source::{Source, mock::MockSource},
    },
    config::UserConfig,
    theme::{self, Theme},
    tui::{
        input::{InputMode, Key},
        layout::PANELS,
        matcher::{Matcher, boxed_default as matcher_default},
        panel::{Panel, PanelState, PanelTag},
        pinout_image::{PinoutImageRenderer, noop_arc as pinout_image_noop_arc},
        popup::Popup,
    },
};

use alloc::sync::Arc;

#[derive(Debug, Clone, Copy)]
pub enum MenuAction { Toggle, Focus, Cancel }

pub struct MenuOption {
    pub key:    Option<char>,
    pub label:  &'static str,
    pub action: MenuAction,
}

pub const SCROLL_STEP: isize = 10;

#[derive(Debug, Clone)]
pub struct CommandLogEntry {
    pub action:  alloc::string::String,
    pub command: alloc::string::String,
}

pub const MENU_OPTIONS: &[MenuOption] = &[
    MenuOption { key: Some('t'), label: "Toggle show/hide command log", action: MenuAction::Toggle },
    MenuOption { key: Some('f'), label: "Focus command log",             action: MenuAction::Focus  },
    MenuOption { key: None,      label: "Cancel",                        action: MenuAction::Cancel },
];

pub struct App {
    pub mode:                InputMode,
    pub focused_index:       usize,
    pub detail_focused:      bool,
    pub states:              Vec<PanelState>,
    pub panel_rects:         Vec<Rect>,
    pub detail_rect:         Rect,
    pub frame_tick:          u32,
    pub should_quit:         bool,
    pub command_log_shown:   bool,
    pub command_log_focused: bool,
    pub command_log_rect:    Rect,
    pub command_log_entries: Vec<CommandLogEntry>,
    pub popups:            Vec<Popup>,
    pub search_history:    VecDeque<String>,
    pub search_history_cursor: Option<usize>,
    pub source:              Box<dyn Source>,
    pub serial:              Box<dyn SerialMonitor>,
    pub build:               Box<dyn BuildRunner>,
    pub probes:              Box<dyn ProbeRegistry>,
    pub probe_list:          Vec<ProbeInfo>,
    pub probe_selection:     usize,
    pub mcumgr_collapsed_groups: BTreeSet<String>,
    pub matcher:             Box<dyn Matcher>,
    pub mcumgr:              Arc<dyn McumgrService>,
    pub pinout_image:        Arc<dyn PinoutImageRenderer>,
    pub config:              UserConfig,
    pub resolved_theme:      Theme,
    pub elf_info:            ElfInfo,
}

impl App {
    pub fn new(
        source:   Box<dyn Source>,
        serial:   Box<dyn SerialMonitor>,
        build:    Box<dyn BuildRunner>,
        probes:   Box<dyn ProbeRegistry>,
        matcher:       Box<dyn Matcher>,
        mcumgr:        Arc<dyn McumgrService>,
        pinout_image:  Arc<dyn PinoutImageRenderer>,
        config:        UserConfig,
        elf_info: ElfInfo,
    ) -> Self {
        let states = (0..PANELS.len()).map(|_| PanelState::default()).collect();
        let initial = 1usize.min(PANELS.len().saturating_sub(1));
        let resolved_theme = theme::resolve(&config.gui);
        let mut app = Self {
            mode:                InputMode::Nav,
            focused_index:       initial,
            detail_focused:      false,
            states,
            panel_rects:         vec![Rect::default(); PANELS.len()],
            detail_rect:         Rect::default(),
            frame_tick:          0,
            should_quit:         false,
            command_log_shown:   config.gui.show_command_log,
            command_log_focused: false,
            command_log_rect:    Rect::default(),
            command_log_entries: Vec::new(),
            popups:            Vec::new(),
            search_history:    VecDeque::new(),
            search_history_cursor: None,
            source,
            serial,
            build,
            probes,
            probe_list:          Vec::new(),
            probe_selection:     0,
            mcumgr_collapsed_groups: BTreeSet::new(),
            matcher,
            mcumgr,
            pinout_image,
            config,
            resolved_theme,
            elf_info,
        };
        app.refresh_probes();
        app
    }

    pub fn with_mock() -> Self {
        Self::new(Box::new(MockSource::new()), noop_box(), build_noop_box(), probes_noop_box(), matcher_default(), mcumgr_noop_arc(), pinout_image_noop_arc(), UserConfig::default(), ElfInfo::default())
    }

    pub fn refresh_probes(&mut self) {
        self.probe_list = self.probes.list();
        if self.probe_selection >= self.probe_list.len() {
            self.probe_selection = 0;
        }
    }

    pub fn theme(&self) -> &Theme { &self.resolved_theme }

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
        self.expire_toasts();
        self.sync_waiting();
    }

    fn sync_waiting(&mut self) {
        let mut pending_error: Option<alloc::string::String> = None;
        self.popups.retain(|p| match p {
            Popup::Waiting { probe, .. } => {
                if probe.is_done() {
                    if let Some(err) = probe.take_error() { pending_error = Some(err); }
                    false
                } else { true }
            }
            _ => true,
        });
        if let Some(err) = pending_error {
            self.alert("Operation failed", err);
        }
    }

    fn expire_toasts(&mut self) {
        let now = self.frame_tick;
        self.popups.retain(|p| match p {
            Popup::Toast { expires_at, .. } => *expires_at > now,
            _ => true,
        });
    }

    pub fn handle_key(&mut self, key: Key) {
        if let Some(overlay) = self.popups.last() {
            match overlay {
                Popup::Menu    { .. } => { self.handle_menu_key(key); return; }
                Popup::Confirm { .. } => { self.handle_confirm_key(key); return; }
                Popup::Alert   { .. } => { self.handle_alert_key(key); return; }
                Popup::Prompt  { .. } => { self.handle_prompt_key(key); return; }
                Popup::Toast   { .. } => {
                    self.popups.retain(|p| !matches!(p, Popup::Toast { .. }));
                }
                Popup::Waiting { .. } => { return; }
                Popup::Help         => {
                    if matches!(key, Key::Char('?') | Key::Esc | Key::Char('q')) {
                        self.popups.pop();
                    }
                    return;
                }
            }
        }
        if self.mode == InputMode::Search {
            self.handle_search_key(key);
            return;
        }
        if matches!(key, Key::Char('@')) {
            self.popups.push(Popup::Menu { selection: 0 });
            return;
        }
        if !matches!(key, Key::Click(..) | Key::ScrollUp(..) | Key::ScrollDown(..))
            && self.current_panel().on_action_key(self, key)
        {
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
        if self.current_panel().tag() == PanelTag::Status && self.detail_focused {
            match key {
                Key::Esc => {
                    self.detail_focused = false;
                    return;
                }
                Key::Char('[') => { self.cycle_detail_tab(-1); return; }
                Key::Char(']') | Key::Char('0') => {
                    self.cycle_detail_tab(1);
                    return;
                }
                Key::Ctrl('u') => { self.current_panel().scroll_detail(self, SCROLL_STEP); return; }
                Key::Ctrl('d') => { self.current_panel().scroll_detail(self, -SCROLL_STEP); return; }
                _ => {}
            }
            if let Some(action_idx) = crate::tui::panes::StatusPanel.selected_action(self) {
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
        match key {
            Key::Char('q')                              => self.should_quit = true,
            Key::Char('?')                              => self.popups.push(Popup::Help),
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

    fn is_serial_at(&self, _x: u16, _y: u16) -> bool { false }

    fn handle_search_key(&mut self, key: Key) {
        match key {
            Key::Esc => {
                let s = self.current_state_mut();
                s.list.filter.clear();
                s.list.select_first();
                self.mode = InputMode::Nav;
                self.search_history_cursor = None;
            }
            Key::Enter => {
                let value = self.current_state().list.filter.clone();
                if !value.is_empty() {
                    self.search_history.retain(|s| s != &value);
                    self.search_history.push_front(value);
                    const MAX: usize = 50;
                    while self.search_history.len() > MAX { self.search_history.pop_back(); }
                }
                self.current_state_mut().list.select_first();
                self.mode = InputMode::Nav;
                self.search_history_cursor = None;
            }
            Key::Up => self.recall_history(1),
            Key::Down => self.recall_history(-1),
            Key::Backspace => {
                let s = self.current_state_mut();
                s.list.filter.pop();
                s.list.select_first();
                self.search_history_cursor = None;
            }
            Key::Char(c) => {
                let s = self.current_state_mut();
                s.list.filter.push(c);
                s.list.select_first();
                self.search_history_cursor = None;
            }
            _ => {}
        }
    }

    fn recall_history(&mut self, dir: isize) {
        if self.search_history.is_empty() { return; }
        let n = self.search_history.len();
        let new_cursor = match (self.search_history_cursor, dir) {
            (None, 1) => Some(0),
            (None, _) => None,
            (Some(c), 1) if c + 1 < n => Some(c + 1),
            (Some(c), -1) if c > 0   => Some(c - 1),
            (Some(_), -1)            => None,
            (cur, _)                 => cur,
        };
        self.search_history_cursor = new_cursor;
        let value = new_cursor
            .and_then(|c| self.search_history.get(c).cloned())
            .unwrap_or_default();
        self.current_state_mut().list.filter = value;
        self.current_state_mut().list.select_first();
    }

    fn handle_menu_key(&mut self, key: Key) {
        let count = MENU_OPTIONS.len();
        let selection = match self.popups.last() {
            Some(Popup::Menu { selection }) => *selection,
            _ => return,
        };
        match key {
            Key::Char('t') | Key::Char('T') => self.activate_menu_option(MenuAction::Toggle),
            Key::Char('f') | Key::Char('F') => self.activate_menu_option(MenuAction::Focus),
            Key::Up   | Key::Char('k')      => {
                if let Some(Popup::Menu { selection }) = self.popups.last_mut() {
                    *selection = (*selection + count - 1) % count;
                }
            }
            Key::Down | Key::Char('j')      => {
                if let Some(Popup::Menu { selection }) = self.popups.last_mut() {
                    *selection = (*selection + 1) % count;
                }
            }
            Key::Enter => {
                if let Some(action) = MENU_OPTIONS.get(selection).map(|o| o.action) {
                    self.activate_menu_option(action);
                }
            }
            Key::Esc | Key::Char('@') | Key::Char('q') => { self.popups.pop(); }
            _ => {}
        }
    }

    fn activate_menu_option(&mut self, action: MenuAction) {
        match action {
            MenuAction::Toggle => self.command_log_shown   = !self.command_log_shown,
            MenuAction::Focus  => self.command_log_focused = true,
            MenuAction::Cancel => {}
        }
        self.popups.pop();
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

    fn handle_confirm_key(&mut self, key: Key) {
        match key {
            Key::Enter => {
                let on_ok = self.popups.iter().rev().find_map(|p| match p {
                    Popup::Confirm { on_confirm, .. } => Some(*on_confirm),
                    _ => None,
                });
                self.popups.pop();
                if let Some(f) = on_ok { f(self); }
            }
            Key::Esc | Key::Char('q') | Key::Char('n') | Key::Char('N') => { self.popups.pop(); }
            _ => {}
        }
    }

    fn handle_alert_key(&mut self, key: Key) {
        if matches!(key, Key::Enter | Key::Esc | Key::Char('q')) {
            self.popups.pop();
        }
    }

    fn handle_prompt_key(&mut self, key: Key) {
        match key {
            Key::Enter => {
                let payload = self.popups.iter().rev().find_map(|p| match p {
                    Popup::Prompt { value, on_submit, .. } => Some((value.clone(), *on_submit)),
                    _ => None,
                });
                self.popups.pop();
                if let Some((value, f)) = payload { f(self, &value); }
            }
            Key::Esc => { self.popups.pop(); }
            Key::Backspace => {
                if let Some(Popup::Prompt { value, cursor, .. }) = self.popups.last_mut() {
                    if *cursor > 0 {
                        let byte = char_byte_index(value, *cursor - 1);
                        value.remove(byte);
                        *cursor -= 1;
                    }
                }
            }
            Key::Left => {
                if let Some(Popup::Prompt { cursor, .. }) = self.popups.last_mut() {
                    *cursor = cursor.saturating_sub(1);
                }
            }
            Key::Right => {
                if let Some(Popup::Prompt { value, cursor, .. }) = self.popups.last_mut() {
                    let max = value.chars().count();
                    if *cursor < max { *cursor += 1; }
                }
            }
            Key::Char(c) => {
                if let Some(Popup::Prompt { value, cursor, .. }) = self.popups.last_mut() {
                    let byte = char_byte_index(value, *cursor);
                    value.insert(byte, c);
                    *cursor += 1;
                }
            }
            _ => {}
        }
    }

    pub fn confirm(&mut self, title: &'static str, message: impl Into<alloc::string::String>, on_confirm: fn(&mut App)) {
        self.popups.push(Popup::Confirm { title, message: message.into(), on_confirm });
    }

    pub fn alert(&mut self, title: &'static str, message: impl Into<alloc::string::String>) {
        self.popups.push(Popup::Alert { title, message: message.into() });
    }

    pub fn prompt(&mut self, title: &'static str, initial: impl Into<alloc::string::String>, on_submit: fn(&mut App, &str)) {
        let value: alloc::string::String = initial.into();
        let cursor = value.chars().count();
        self.popups.push(Popup::Prompt { title, value, cursor, on_submit });
    }

    pub fn toast(&mut self, message: impl Into<alloc::string::String>) {
        self.push_toast(message.into(), crate::tui::popup::ToastKind::Success);
    }

    pub fn info_toast(&mut self, message: impl Into<alloc::string::String>) {
        self.push_toast(message.into(), crate::tui::popup::ToastKind::Info);
    }

    pub fn error_toast(&mut self, message: impl Into<alloc::string::String>) {
        self.push_toast(message.into(), crate::tui::popup::ToastKind::Error);
    }

    fn push_toast(&mut self, message: alloc::string::String, kind: crate::tui::popup::ToastKind) {
        const TOAST_FRAMES: u32 = 90;
        let expires_at = self.frame_tick.wrapping_add(TOAST_FRAMES);
        self.popups.retain(|p| !matches!(p, Popup::Toast { .. }));
        self.popups.push(Popup::Toast { message, kind, expires_at });
    }
}

fn char_byte_index(s: &str, char_idx: usize) -> usize {
    s.char_indices().map(|(i, _)| i).nth(char_idx).unwrap_or(s.len())
}
