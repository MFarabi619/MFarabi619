use alloc::{collections::BTreeMap, format, string::{String, ToString}, vec, vec::Vec};

use ratatui::{
    Frame,
    layout::Rect,
    macros::line,
    style::Stylize,
    text::Line,
    widgets::{List, ListItem, Paragraph, Wrap},
};

use crate::tui::{
    devicetree,
    keybindings::{ACTION_TAG, Binding},
    panel::{Panel, PanelTag},
    render::{kv, overlay_panel_tabs, placeholder_paragraph, selection_style, selection_symbol, titled_list_block},
    state::App,
};

const TABS: &[&str] = &["Targets", "Boards", "Echo"];
const TAB_TARGETS: usize = 0;
const TAB_BOARDS:  usize = 1;
const TAB_ECHO:    usize = 2;

const BOARD_DETAIL_TABS: &[&str] = &["Pinout", "Image"];

const ECHO_ENTRIES: &[McumgrEntry] = &[
    McumgrEntry { label: "Echo", icon: "\u{f0ad}" },
];

const BOARD_ENTRIES: &[McumgrEntry] = &[
    McumgrEntry { label: "xiao_esp32s3",   icon: "\u{f2db}" },
    McumgrEntry { label: "walter_esp32s3", icon: "\u{f2db}" },
];

struct McumgrEntry {
    label: &'static str,
    icon:  &'static str,
}

const CHIP_TABLE: &[(u16, u16, &str)] = &[
    (0x303a, 0x1001, "ESP32-S3: xtensa LX7"),
    (0x303a, 0x1002, "ESP32-C3: RISC-V"),
    (0x303a, 0x1003, "ESP32-S2: xtensa LX7"),
    (0x303a, 0x1005, "ESP32-C6: RISC-V"),
    (0x303a, 0x4001, "ESP32-P4: RISC-V"),
    (0x303a, 0x4002, "ESP32-C5: RISC-V"),
    (0x303a, 0x0002, "ESP32: xtensa LX6 (UART bridge)"),
    (0x10c4, 0xea60, "CP2102 USB-UART"),
    (0x1a86, 0x7523, "CH340 USB-UART"),
    (0x0483, 0x374e, "ST-Link V3"),
    (0x0483, 0x374b, "ST-Link V2.1"),
    (0x0483, 0x3748, "ST-Link V2"),
    (0x1366, 0x1015, "SEGGER J-Link"),
    (0x0d28, 0x0204, "CMSIS-DAP / DAPLink"),
    (0x1d50, 0x6018, "Black Magic Probe"),
];

fn chip_family(vid: u16, pid: u16) -> Option<&'static str> {
    CHIP_TABLE.iter().find(|(v, p, _)| *v == vid && *p == pid).map(|(_, _, s)| *s)
}

fn vendor_name(vid: u16) -> Option<&'static str> {
    match vid {
        0x303a => Some("Espressif"),
        0x0483 => Some("STMicroelectronics"),
        0x1366 => Some("SEGGER"),
        0x0d28 => Some("ARM"),
        0x1d50 => Some("OpenMoko"),
        0x10c4 => Some("Silicon Labs"),
        0x1a86 => Some("WCH"),
        _      => None,
    }
}

fn probe_icon(probe_type: &str) -> &'static str {
    let lower = probe_type.to_ascii_lowercase();
    if lower.contains("jtag") { "\u{f1e6}" }
    else if lower.contains("swd") || lower.contains("stlink")
         || lower.contains("st_link") || lower.contains("cmsis") { "\u{eb83}" }
    else { "\u{f065c}" }
}

fn group_key_for(identifier: &str, vid: u16, pid: u16) -> String {
    format!("{}|{:04x}:{:04x}", identifier, vid, pid)
}

#[derive(Debug, Clone)]
enum TargetRow {
    Group {
        key:        String,
        label:      String,
        vid_pid:    String,
        vid:        u16,
        pid:        u16,
        probe_type: String,
        count:      usize,
        expanded:   bool,
    },
    Leaf {
        probe_idx: usize,
        is_last:   bool,
        group_key: String,
    },
}

fn target_rows(app: &App) -> Vec<TargetRow> {
    let mut groups: BTreeMap<String, Vec<usize>> = BTreeMap::new();
    for (i, probe) in app.probe_list.iter().enumerate() {
        let key = group_key_for(&probe.identifier, probe.vendor_id, probe.product_id);
        groups.entry(key).or_default().push(i);
    }
    let mut rows = Vec::new();
    for (key, idxs) in groups {
        let first = &app.probe_list[idxs[0]];
        let expanded = !app.mcumgr_collapsed_groups.contains(&key);
        rows.push(TargetRow::Group {
            key:        key.clone(),
            label:      first.identifier.clone(),
            vid_pid:    format!("{:04x}:{:04x}", first.vendor_id, first.product_id),
            vid:        first.vendor_id,
            pid:        first.product_id,
            probe_type: first.probe_type.clone(),
            count:      idxs.len(),
            expanded,
        });
        if expanded {
            let last = idxs.len() - 1;
            for (j, probe_idx) in idxs.into_iter().enumerate() {
                rows.push(TargetRow::Leaf {
                    probe_idx,
                    is_last: j == last,
                    group_key: key.clone(),
                });
            }
        }
    }
    rows
}

pub struct McumgrPanel;

impl Panel for McumgrPanel {
    fn tag(&self) -> PanelTag { PanelTag::Mcumgr }
    fn label(&self) -> &'static str { "mcumgr" }
    fn inner_tabs(&self) -> &'static [&'static str] { TABS }

    fn detail_tabs(&self, app: &App) -> Vec<&'static str> {
        match app.state_of(self.tag()).list_tab {
            TAB_TARGETS => vec!["Probe"],
            TAB_BOARDS  => BOARD_DETAIL_TABS.to_vec(),
            _           => vec!["Echo"],
        }
    }

    fn list_len(&self, app: &App) -> usize {
        match app.state_of(self.tag()).list_tab {
            TAB_TARGETS => target_rows(app).len(),
            TAB_BOARDS  => BOARD_ENTRIES.len(),
            _           => ECHO_ENTRIES.len(),
        }
    }

    fn current_name(&self, app: &App) -> String {
        let state = app.state_of(self.tag());
        let idx = state.list.selected().unwrap_or(0);
        match state.list_tab {
            TAB_TARGETS => match target_rows(app).into_iter().nth(idx) {
                Some(TargetRow::Group { label, .. }) => label,
                Some(TargetRow::Leaf { probe_idx, .. }) => app.probe_list.get(probe_idx)
                    .and_then(|p| p.serial_number.clone())
                    .unwrap_or_default(),
                None => String::new(),
            },
            TAB_BOARDS => BOARD_ENTRIES.get(idx).map(|e| e.label.into()).unwrap_or_default(),
            _          => ECHO_ENTRIES.get(idx).map(|e| e.label.into()).unwrap_or_default(),
        }
    }

    fn bindings(&self, app: &App) -> Vec<Binding> {
        match app.state_of(self.tag()).list_tab {
            TAB_TARGETS => alloc::vec![
                Binding::new(&["Space"], "build firmware").footer().short("Build").tag(ACTION_TAG).handler(targets_build),
                Binding::new(&["Enter"], "flash + monitor / toggle group").footer().short("Flash+Monitor").tag(ACTION_TAG).handler(targets_enter),
                Binding::new(&["Tab"],   "expand / collapse group").footer().short("Toggle").tag(ACTION_TAG).handler(targets_toggle),
                Binding::new(&["r"],     "rescan probes").footer().short("Rescan").tag(ACTION_TAG).handler(targets_rescan),
            ],
            TAB_ECHO => alloc::vec![
                Binding::new(&["r"], "ping echo now").footer().short("Ping").tag(ACTION_TAG).handler(ping_now),
            ],
            _ => Vec::new(),
        }
    }

    fn render_list(&self, frame: &mut Frame, area: Rect, app: &mut App, focused: bool) {
        let theme    = *app.theme();
        let state    = app.state_of(self.tag());
        let active   = state.list_tab;
        let selected = state.list.selected();
        let panel_idx = app.index_of(self.tag()) + 1;
        let show_jumps = app.config.gui.show_panel_jumps;

        let (items, total): (Vec<ListItem>, usize) = match active {
            TAB_TARGETS => {
                let rows = target_rows(app);
                let items: Vec<ListItem> = rows.iter().map(|row| match row {
                    TargetRow::Group { label, vid_pid, count, expanded, probe_type, vid, pid, .. } => {
                        let chevron = if *expanded { "\u{25bc} " } else { "\u{25b6} " };
                        let icon = probe_icon(probe_type);
                        let display = chip_family(*vid, *pid).map(alloc::string::String::from)
                                                             .unwrap_or_else(|| label.clone());
                        ListItem::new(line![
                            chevron.fg(theme.muted),
                            format!("{} ", icon).fg(theme.success),
                            display.fg(theme.foreground),
                            format!(" \u{b7} {}", vid_pid).fg(theme.muted),
                            format!("  [{}]", count).fg(theme.muted),
                        ])
                    }
                    TargetRow::Leaf { probe_idx, is_last, .. } => {
                        let probe = &app.probe_list[*probe_idx];
                        let connector = if *is_last { "\u{2514}\u{2500} " } else { "\u{251c}\u{2500} " };
                        let mac = probe.serial_number.clone().unwrap_or_else(|| "\u{2014}".into());
                        let dev = probe.device_path.clone().unwrap_or_else(|| "(no /dev)".into());
                        ListItem::new(line![
                            connector.fg(theme.muted),
                            "\u{25cf} ".fg(theme.muted),
                            format!("{:<18}", mac).fg(theme.foreground),
                            format!("  {}", dev).fg(theme.muted),
                        ])
                    }
                }).collect();
                let len = items.len();
                (items, len)
            }
            tab => {
                let entries: &[McumgrEntry] = match tab {
                    TAB_BOARDS => BOARD_ENTRIES,
                    _          => ECHO_ENTRIES,
                };
                let items: Vec<ListItem> = entries.iter().map(|e| {
                    ListItem::new(line![
                        format!("{} ", e.icon).fg(theme.accent),
                        e.label.to_string().fg(theme.foreground),
                    ])
                }).collect();
                (items, entries.len())
            }
        };

        let block = titled_list_block(&theme, Line::raw(""), focused, selected, total);
        let list = List::new(items).block(block)
            .highlight_style(selection_style(&theme, focused))
            .highlight_symbol(selection_symbol(focused));
        let idx = app.index_of(self.tag());
        frame.render_stateful_widget(list, area, &mut app.states[idx].list.list);
        overlay_panel_tabs(frame, area, &theme, panel_idx, TABS, active, focused, show_jumps);
    }

    fn render_detail(&self, frame: &mut Frame, area: Rect, app: &mut App, tab: &str) {
        let state  = app.state_of(self.tag());
        let active = state.list_tab;
        let idx    = state.list.selected().unwrap_or(0);
        match active {
            TAB_TARGETS => render_targets_detail(frame, area, app, idx),
            TAB_BOARDS  => match tab {
                "Image" => {
                    let board = BOARD_ENTRIES.get(idx).map(|e| e.label).unwrap_or("");
                    app.pinout_image.clone().render(frame, area, board);
                }
                _ => devicetree::render(frame, area, app),
            },
            _ => render_echo(frame, area, app),
        }
    }
}

fn ping_now(app: &mut App) {
    app.mcumgr.ping_async(app.frame_tick);
}

fn targets_build(app: &mut App) {
    app.log_command("Build", "west bx");
}

fn targets_enter(app: &mut App) {
    let rows = target_rows(app);
    let idx  = app.state_of(PanelTag::Mcumgr).list.selected().unwrap_or(0);
    match rows.into_iter().nth(idx) {
        Some(TargetRow::Group { key, .. }) => toggle_group_at_cursor(app, key, idx),
        Some(TargetRow::Leaf { probe_idx, .. }) => flash_probe(app, probe_idx),
        None => {}
    }
}

fn targets_toggle(app: &mut App) {
    let rows = target_rows(app);
    let idx  = app.state_of(PanelTag::Mcumgr).list.selected().unwrap_or(0);
    let (key, group_idx) = match rows.iter().nth(idx) {
        Some(TargetRow::Group { key, .. }) => (key.clone(), idx),
        Some(TargetRow::Leaf { group_key, .. }) => {
            let g = rows.iter().position(|r| matches!(r, TargetRow::Group { key: k, .. } if k == group_key));
            (group_key.clone(), g.unwrap_or(idx))
        }
        None => return,
    };
    toggle_group_at_cursor(app, key, group_idx);
}

fn toggle_group_at_cursor(app: &mut App, key: String, group_row_idx: usize) {
    if app.mcumgr_collapsed_groups.contains(&key) {
        app.mcumgr_collapsed_groups.remove(&key);
    } else {
        app.mcumgr_collapsed_groups.insert(key);
    }
    let state = app.state_of_mut(PanelTag::Mcumgr);
    state.list.list.select(Some(group_row_idx));
}

fn flash_probe(app: &mut App, probe_idx: usize) {
    let Some(probe) = app.probe_list.get(probe_idx).cloned() else { return; };
    let identifier = probe.identifier;
    let path       = probe.device_path.unwrap_or_else(|| "<no /dev>".into());
    let serial     = probe.serial_number.unwrap_or_else(|| "<no serial>".into());
    app.log_command(
        format!("Flash+Monitor ({identifier})"),
        format!("west flash --runner probe-rs --probe {serial} && tio {path} -b 115200"),
    );
}

fn targets_rescan(app: &mut App) {
    app.refresh_probes();
}

fn render_targets_detail(frame: &mut Frame, area: Rect, app: &App, idx: usize) {
    let theme = *app.theme();
    let rows  = target_rows(app);
    match rows.into_iter().nth(idx) {
        Some(TargetRow::Group { label, vid, pid, count, .. }) => {
            let mut lines: Vec<Line<'static>> = Vec::new();
            let header = format!("{count} {} detected", if count == 1 { "probe" } else { "probes" });
            lines.push(Line::from(header.fg(theme.value).bold()));
            lines.push(Line::raw(""));
            lines.push(kv(&theme, "family", label));
            if let Some(chip) = chip_family(vid, pid) {
                lines.push(kv(&theme, "target chip", chip.into()));
            }
            let vendor = vendor_name(vid).map(|n| format!("{:04x} ({n})", vid))
                                         .unwrap_or_else(|| format!("{:04x}", vid));
            lines.push(kv(&theme, "vendor", vendor));
            lines.push(kv(&theme, "vid:pid", format!("{:04x}:{:04x}", vid, pid)));
            lines.push(Line::raw(""));
            lines.push(Line::from("Enter / Tab to expand or collapse.".fg(theme.label)));
            frame.render_widget(Paragraph::new(lines).wrap(Wrap { trim: false }), area);
        }
        Some(TargetRow::Leaf { probe_idx, .. }) => render_probe_leaf(frame, area, app, probe_idx),
        None => {
            frame.render_widget(placeholder_paragraph(&theme, "no debug probe detected \u{2014} press r to rescan"), area);
        }
    }
}

fn render_probe_leaf(frame: &mut Frame, area: Rect, app: &App, probe_idx: usize) {
    let theme = *app.theme();
    let Some(probe) = app.probe_list.get(probe_idx) else { return; };
    let serial = probe.serial_number.clone().unwrap_or_else(|| "\u{2014}".into());
    let path   = probe.device_path.clone().unwrap_or_else(|| "(no /dev match)".into());
    let mut lines: Vec<Line<'static>> = Vec::new();
    if let Some(chip) = chip_family(probe.vendor_id, probe.product_id) {
        lines.push(kv(&theme, "target chip", chip.into()));
    }
    lines.push(kv(&theme, "descriptor", probe.identifier.clone()));
    let vendor = vendor_name(probe.vendor_id)
        .map(|n| format!("{:04x} ({n})", probe.vendor_id))
        .unwrap_or_else(|| format!("{:04x}", probe.vendor_id));
    lines.push(kv(&theme, "vendor", vendor));
    lines.push(kv(&theme, "serial",  serial));
    lines.push(kv(&theme, "device",  path));
    frame.render_widget(Paragraph::new(lines).wrap(Wrap { trim: false }), area);
}

fn render_echo(frame: &mut Frame, area: Rect, app: &App) {
    let theme = *app.theme();
    let state = app.mcumgr.echo_state();
    let mut rows: Vec<Line<'static>> = Vec::new();
    let status_label = if state.busy { "pinging\u{2026}" }
                       else if state.last_error.is_some() { "error" }
                       else if state.last.is_some() { "ok" }
                       else { "idle" };
    let status_color = if state.busy { theme.warning }
                       else if state.last_error.is_some() { theme.error }
                       else if state.last.is_some() { theme.success }
                       else { theme.label };
    rows.push(kv(&theme, "status", status_label.into()));
    rows.push(line![
        format!("{:<14}", "indicator").fg(theme.label),
        "\u{25cf} ".fg(status_color).bold(),
        status_label.fg(status_color).bold(),
    ]);
    if let Some(sample) = &state.last {
        rows.push(kv(&theme, "latency", format!("{} ms", sample.latency_ms)));
        rows.push(kv(&theme, "response", sample.response.clone()));
    }
    if let Some(err) = &state.last_error {
        rows.push(line![
            format!("{:<14}", "error").fg(theme.label),
            err.clone().fg(theme.error),
        ]);
    }
    if state.last.is_none() && state.last_error.is_none() && !state.busy {
        frame.render_widget(placeholder_paragraph(&theme, "press r to ping"), area);
        return;
    }
    frame.render_widget(Paragraph::new(rows).wrap(Wrap { trim: false }), area);
}
