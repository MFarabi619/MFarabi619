use alloc::{format, string::{String, ToString}, vec, vec::Vec};

use ratatui::{
    Frame,
    layout::Rect,
    style::{Style, Stylize},
    text::{Line, Span},
    widgets::{List, ListItem, Paragraph, Wrap},
};

use crate::{
    app::App,
    input::Key,
    panel::{Panel, PanelTag},
    probes::ProbeInfo,
    serial::SerialStatus,
    theme::Theme,
    ui::widgets::{panel_title, selection_style, selection_symbol, titled_list_block},
};

#[derive(Debug, Clone, Copy)]
pub enum WestEntry {
    Monitor,
    Build(usize),
}

pub struct StatusPanel;

impl StatusPanel {
    fn entries(&self, app: &App) -> Vec<WestEntry> {
        let mut out = vec![WestEntry::Monitor];
        for i in 0..app.build.actions().len() {
            out.push(WestEntry::Build(i));
        }
        out
    }

    pub fn selected_entry(&self, app: &App) -> WestEntry {
        let entries = self.entries(app);
        let idx = app.state_of(self.tag()).list.selected().unwrap_or(0);
        entries.get(idx).copied().unwrap_or(WestEntry::Monitor)
    }
}

impl Panel for StatusPanel {
    fn tag(&self) -> PanelTag { PanelTag::Status }
    fn label(&self) -> &'static str { "West" }

    fn detail_tabs(&self, app: &App) -> Vec<&'static str> {
        match self.selected_entry(app) {
            WestEntry::Monitor => vec!["Serial"],
            WestEntry::Build(idx) => {
                app.build.actions().get(idx).map(|a| {
                    if a.tabs.is_empty() { vec![a.name] } else { a.tabs.to_vec() }
                }).unwrap_or_else(|| vec!["(no action)"])
            }
        }
    }

    fn list_len(&self, app: &App) -> usize {
        self.entries(app).len()
    }

    fn current_name(&self, app: &App) -> String {
        match self.selected_entry(app) {
            WestEntry::Monitor => "Monitor".into(),
            WestEntry::Build(idx) => app.build.actions().get(idx).map(|a| a.name.into()).unwrap_or_default(),
        }
    }

    fn footer_actions(&self, app: &App) -> Vec<crate::panel::FooterAction> {
        match self.selected_entry(app) {
            WestEntry::Monitor   => alloc::vec![("Clear", "c")],
            WestEntry::Build(_)  => alloc::vec![("Refresh", "r")],
        }
    }

    fn render_list(&self, frame: &mut Frame, area: Rect, app: &mut App, focused: bool) {
        let theme    = *app.theme();
        let title    = panel_title(&theme, app.index_of(self.tag()) + 1, self.label(), focused, false);
        let total    = self.list_len(app);
        let selected = app.state_of(self.tag()).list.selected();
        let block    = titled_list_block(&theme, title, focused, selected, total);

        let actions = app.build.actions();
        let mut items: Vec<ListItem> = Vec::with_capacity(actions.len() + 1);

        let serial_dot = match app.serial.status_line() {
            SerialStatus::Streaming  => theme.success,
            SerialStatus::Connecting => theme.warning,
            SerialStatus::Exited     => theme.error,
            SerialStatus::Disabled   => theme.label,
        };
        items.push(ListItem::new(Line::from(vec![
            Span::raw("\u{f0c1d} ").fg(serial_dot).bold(),
            Span::raw("Monitor").fg(theme.value).bold(),
        ])));

        for action in actions {
            items.push(ListItem::new(Line::from(vec![
                Span::raw(format!("{} ", action.icon)).fg(theme.value).bold(),
                Span::raw(action.name.to_string()).fg(theme.value).bold(),
            ])));
        }

        let list = List::new(items).block(block)
            .highlight_style(selection_style(&theme, focused))
            .highlight_symbol(selection_symbol(focused));
        let state = &mut app.state_of_mut(self.tag()).list.state;
        frame.render_stateful_widget(list, area, state);
    }

    fn render_detail(&self, frame: &mut Frame, area: Rect, app: &mut App, tab: &str) {
        let theme = *app.theme();
        match self.selected_entry(app) {
            WestEntry::Monitor => {
                if app.serial.status_line() == SerialStatus::Disabled {
                    render_ports_popup(frame, area, &theme, &app.probe_list, app.probe_selection);
                } else {
                    app.serial.render(frame, area, &theme);
                }
            }
            WestEntry::Build(action_idx) => {
                let Some(action) = app.build.actions().get(action_idx).cloned() else {
                    frame.render_widget(
                        Paragraph::new(Span::raw("no build action").fg(theme.label)),
                        area,
                    );
                    return;
                };
                let tab_idx = if action.tabs.is_empty() {
                    0
                } else {
                    action.tabs.iter().position(|t| *t == tab).unwrap_or(0)
                };
                if let Some(cmd) = app.build.ensure_spawned(action_idx, tab_idx) {
                    let label = if action.tabs.is_empty() {
                        format!("West: {}", action.name)
                    } else {
                        format!("West: {} / {}", action.name, action.tabs[tab_idx])
                    };
                    app.log_command(label, cmd);
                }
                app.build.render(action_idx, tab_idx, frame, area, &theme);
            }
        }
    }

    fn scroll_detail(&self, app: &mut App, lines: isize) {
        match self.selected_entry(app) {
            WestEntry::Monitor => app.serial.scroll(lines),
            WestEntry::Build(action_idx) => {
                let tab_idx = active_build_tab_idx(app, action_idx);
                app.build.scroll(action_idx, tab_idx, lines);
            }
        }
    }

    fn on_action_key(&self, app: &mut App, key: Key) -> bool {
        if let WestEntry::Build(action_idx) = self.selected_entry(app) {
            if matches!(key, Key::Char('r')) {
                let tab_idx = active_build_tab_idx(app, action_idx);
                app.build.refresh(action_idx, tab_idx);
                return true;
            }
        }
        false
    }
}

fn active_build_tab_idx(app: &App, action_idx: usize) -> usize {
    let detail_tab = app.state_of(PanelTag::Status).detail_tab;
    let Some(action) = app.build.actions().get(action_idx) else { return 0; };
    if action.tabs.is_empty() { 0 } else { detail_tab.min(action.tabs.len().saturating_sub(1)) }
}

fn render_ports_popup(
    frame:     &mut Frame,
    area:      Rect,
    theme:     &Theme,
    probes:    &[ProbeInfo],
    selection: usize,
) {
    use ratatui::widgets::{Block, Clear};

    let rows_for_probes = probes.len().max(1) as u16;
    let desired_height = 4 + rows_for_probes;
    let width  = 72u16.min(area.width.saturating_sub(2));
    let height = desired_height.min(area.height.saturating_sub(2));
    let popup = Rect {
        x:      area.x + area.width.saturating_sub(width)  / 2,
        y:      area.y + area.height.saturating_sub(height) / 2,
        width,
        height,
    };
    frame.render_widget(Clear, popup);

    let block = Block::bordered()
        .border_style(Style::new().fg(theme.accent))
        .title(Span::raw(" Ports ").fg(theme.accent).bold());
    let inner = block.inner(popup);
    frame.render_widget(block, popup);
    if inner.height == 0 { return; }

    let mut lines: Vec<Line<'static>> = Vec::new();

    if probes.is_empty() {
        lines.push(Line::from(""));
        lines.push(Line::from(vec![
            Span::raw(" No debug probes detected.").fg(theme.label),
        ]));
        lines.push(Line::from(vec![
            Span::raw(" Press ").fg(theme.label),
            Span::raw("r").fg(theme.accent).bold(),
            Span::raw(" to refresh.").fg(theme.label),
        ]));
    } else {
        for (idx, probe) in probes.iter().enumerate() {
            let selected = idx == selection;
            let marker = if selected { "▶ " } else { "  " };
            let marker_color = if selected { theme.accent } else { theme.border };
            let id_color    = if selected { theme.accent } else { theme.value };
            let path_color  = if selected { theme.success } else { theme.label };
            let id_style    = if selected {
                Style::new().fg(id_color).add_modifier(ratatui::style::Modifier::BOLD)
            } else {
                Style::new().fg(id_color)
            };

            let path = probe.device_path.clone().unwrap_or_else(|| "(no /dev match)".into());
            let serial = probe.serial_number.clone().unwrap_or_else(|| "—".into());
            let vidpid = format!("{:04x}:{:04x}", probe.vendor_id, probe.product_id);

            lines.push(Line::from(vec![
                Span::raw(marker.to_string()).style(Style::new().fg(marker_color)),
                Span::raw(probe.identifier.clone()).style(id_style),
                Span::raw("  ").fg(theme.label),
                Span::raw(probe.probe_type.clone()).fg(theme.label),
            ]));
            lines.push(Line::from(vec![
                Span::raw("    ").fg(theme.label),
                Span::raw(vidpid).fg(theme.label),
                Span::raw("  sn ").fg(theme.label),
                Span::raw(serial).fg(theme.value),
                Span::raw("  ").fg(theme.label),
                Span::raw(path).fg(path_color),
            ]));
        }
    }

    lines.push(Line::from(""));
    lines.push(Line::from(vec![
        Span::raw(" ").fg(theme.label),
        Span::raw("↑/↓").fg(theme.accent).bold(),
        Span::raw(" select  ").fg(theme.label),
        Span::raw("Enter").fg(theme.accent).bold(),
        Span::raw(" begin  ").fg(theme.label),
        Span::raw("r").fg(theme.accent).bold(),
        Span::raw(" refresh  ").fg(theme.label),
        Span::raw("Esc").fg(theme.accent).bold(),
        Span::raw(" cancel").fg(theme.label),
    ]));

    frame.render_widget(Paragraph::new(lines).wrap(Wrap { trim: false }), inner);
}
