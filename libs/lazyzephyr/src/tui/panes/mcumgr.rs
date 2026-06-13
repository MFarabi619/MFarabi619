use alloc::{collections::BTreeMap, format, string::{String, ToString}, vec, vec::Vec};

use ratatui::{
    Frame,
    layout::Rect,
    macros::line,
    style::Stylize,
    text::Line,
    widgets::{List, ListItem, Paragraph, Wrap},
};

use crate::{
    theme::Theme,
    tui::{
        devicetree,
        keybindings::{ACTION_TAG, Binding},
        panel::{Panel, PanelTag},
        render::{kv, overlay_panel_tabs, placeholder_paragraph, selection_style, selection_symbol, titled_list_block},
        state::App,
    },
};

const TABS: &[&str] = &["Probes", "Boards", "Echo"];
const TAB_PROBES: usize = 0;
const TAB_BOARDS:  usize = 1;
const TAB_ECHO:    usize = 2;

const BOARD_DETAIL_TABS: &[&str] = &["Pinout", "Image"];

const ECHO_ENTRIES: &[McumgrEntry] = &[
    McumgrEntry { label: "Echo", icon: "\u{f0ad}" },
];

struct McumgrEntry {
    label: &'static str,
    icon:  &'static str,
}

#[derive(Debug, Clone)]
enum BoardRow {
    Group { vendor: String, count: usize, expanded: bool },
    Leaf  { board_idx: usize, is_last: bool },
}

fn board_rows(app: &App) -> Vec<BoardRow> {
    let filter = app.state_of(PanelTag::Mcumgr).list.filter.to_ascii_lowercase();
    let matches = |b: &crate::commands::workspace::WestBoard| {
        if filter.is_empty() { return true; }
        b.name.to_ascii_lowercase().contains(&filter)
            || b.full_name.to_ascii_lowercase().contains(&filter)
            || b.vendor.to_ascii_lowercase().contains(&filter)
    };
    let mut groups: BTreeMap<String, Vec<usize>> = BTreeMap::new();
    for (i, board) in app.workspace.boards.iter().enumerate() {
        if !matches(board) { continue; }
        let vendor = if board.vendor.is_empty() { "(unknown)".into() } else { board.vendor.clone() };
        groups.entry(vendor).or_default().push(i);
    }
    for idxs in groups.values_mut() {
        idxs.sort_by(|&a, &b| app.workspace.boards[a].name.cmp(&app.workspace.boards[b].name));
    }
    let mut rows = Vec::new();
    for (vendor, idxs) in groups {
        let expanded = !app.boards_collapsed_vendors.contains(&vendor);
        let count    = idxs.len();
        rows.push(BoardRow::Group { vendor: vendor.clone(), count, expanded });
        if expanded {
            let last = idxs.len() - 1;
            for (j, board_idx) in idxs.into_iter().enumerate() {
                rows.push(BoardRow::Leaf { board_idx, is_last: j == last });
            }
        }
    }
    rows
}

fn selected_board_idx(app: &App) -> Option<usize> {
    let idx = app.state_of(PanelTag::Mcumgr).list.selected().unwrap_or(0);
    match board_rows(app).into_iter().nth(idx) {
        Some(BoardRow::Leaf { board_idx, .. }) => Some(board_idx),
        _ => None,
    }
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
enum ProbeRow {
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

fn probe_rows(app: &App) -> Vec<ProbeRow> {
    let filter = app.state_of(PanelTag::Mcumgr).list.filter.to_ascii_lowercase();
    let matches = |probe: &crate::commands::probes::ProbeInfo| {
        if filter.is_empty() { return true; }
        probe.serial_number.as_deref().map(|s| s.to_ascii_lowercase().contains(&filter)).unwrap_or(false)
            || probe.device_path.as_deref().map(|s| s.to_ascii_lowercase().contains(&filter)).unwrap_or(false)
            || probe.identifier.to_ascii_lowercase().contains(&filter)
    };
    if app.probes_flat {
        let mut idxs: Vec<usize> = (0..app.probe_list.len()).filter(|&i| matches(&app.probe_list[i])).collect();
        idxs.sort_by(|&a, &b| {
            let device_a = app.probe_list[a].device_path.as_deref();
            let device_b = app.probe_list[b].device_path.as_deref();
            device_a.is_none().cmp(&device_b.is_none()).then(device_a.cmp(&device_b))
        });
        return idxs.into_iter().map(|probe_idx| ProbeRow::Leaf {
            probe_idx,
            is_last: false,
            group_key: String::new(),
        }).collect();
    }
    let mut groups: BTreeMap<String, Vec<usize>> = BTreeMap::new();
    for (i, probe) in app.probe_list.iter().enumerate() {
        if !matches(probe) { continue; }
        let key = group_key_for(&probe.identifier, probe.vendor_id, probe.product_id);
        groups.entry(key).or_default().push(i);
    }
    for idxs in groups.values_mut() {
        idxs.sort_by(|&a, &b| {
            let device_a = app.probe_list[a].device_path.as_deref();
            let device_b = app.probe_list[b].device_path.as_deref();
            device_a.is_none().cmp(&device_b.is_none()).then(device_a.cmp(&device_b))
        });
    }
    let mut rows = Vec::new();
    for (key, idxs) in groups {
        let first = &app.probe_list[idxs[0]];
        let expanded = !app.mcumgr_collapsed_groups.contains(&key);
        rows.push(ProbeRow::Group {
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
                rows.push(ProbeRow::Leaf {
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
            TAB_PROBES => vec!["Serial"],
            TAB_BOARDS  => BOARD_DETAIL_TABS.to_vec(),
            _           => vec!["Echo"],
        }
    }

    fn list_len(&self, app: &App) -> usize {
        match app.state_of(self.tag()).list_tab {
            TAB_PROBES => probe_rows(app).len(),
            TAB_BOARDS  => board_rows(app).len(),
            _           => ECHO_ENTRIES.len(),
        }
    }

    fn current_name(&self, app: &App) -> String {
        let state = app.state_of(self.tag());
        let idx = state.list.selected().unwrap_or(0);
        match state.list_tab {
            TAB_PROBES => match probe_rows(app).into_iter().nth(idx) {
                Some(ProbeRow::Group { label, .. }) => label,
                Some(ProbeRow::Leaf { probe_idx, .. }) => app.probe_list.get(probe_idx)
                    .and_then(|p| p.serial_number.clone())
                    .unwrap_or_default(),
                None => String::new(),
            },
            TAB_BOARDS => match board_rows(app).into_iter().nth(idx) {
                Some(BoardRow::Group { vendor, .. }) => vendor,
                Some(BoardRow::Leaf { board_idx, .. }) => app.workspace.boards.get(board_idx).map(|b| b.name.clone()).unwrap_or_default(),
                None => String::new(),
            },
            _          => ECHO_ENTRIES.get(idx).map(|e| e.label.into()).unwrap_or_default(),
        }
    }

    fn bindings(&self, app: &App) -> Vec<Binding> {
        match app.state_of(self.tag()).list_tab {
            TAB_PROBES => alloc::vec![
                Binding::new(&["Space"], "build firmware").footer().short("Build").tag(ACTION_TAG).handler(probes_build),
                Binding::new(&["f"],     "flash firmware").footer().short("Flash").tag(ACTION_TAG).handler(probes_flash),
                Binding::new(&["Enter"], "monitor / toggle group").footer().short("Monitor").tag(ACTION_TAG).handler(probes_enter),
                Binding::new(&["Tab"],   "expand / collapse group").footer().short("Toggle").tag(ACTION_TAG).handler(probes_toggle),
                Binding::new(&["`"],     "toggle tree view").footer().short("Tree").tag(ACTION_TAG).handler(probes_toggle_view),
                Binding::new(&["r"],     "rescan probes").footer().short("Rescan").tag(ACTION_TAG).handler(probes_rescan),
            ],
            TAB_BOARDS => alloc::vec![
                Binding::new(&["Enter"], "toggle vendor").footer().short("Toggle").tag(ACTION_TAG).handler(boards_toggle),
                Binding::new(&["Tab"],   "toggle vendor").footer().short("Toggle").tag(ACTION_TAG).handler(boards_toggle),
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
            TAB_PROBES => {
                let rows = probe_rows(app);
                let items: Vec<ListItem> = rows.iter().map(|row| match row {
                    ProbeRow::Group { label, vid_pid, expanded, probe_type, vid, pid, .. } => {
                        let chevron = if *expanded { "\u{25bc} " } else { "\u{25b6} " };
                        let icon = probe_icon(probe_type);
                        let display = chip_family(*vid, *pid).map(alloc::string::String::from)
                                                             .unwrap_or_else(|| label.clone());
                        ListItem::new(line![
                            chevron.fg(theme.muted),
                            format!("{} ", icon).fg(theme.success),
                            display.fg(theme.foreground),
                            format!(" \u{b7} {}", vid_pid).fg(theme.muted),
                        ])
                    }
                    ProbeRow::Leaf { probe_idx, is_last, .. } => {
                        let probe = &app.probe_list[*probe_idx];
                        let mac = probe.serial_number.clone().unwrap_or_else(|| "\u{2014}".into());
                        let dev = probe.device_path.clone().unwrap_or_else(|| "(no /dev)".into());
                        if app.probes_flat {
                            let icon = probe_icon(&probe.probe_type);
                            ListItem::new(line![
                                format!("{} ", icon).fg(theme.success),
                                mac.fg(theme.foreground),
                                format!(" {}", dev).fg(theme.muted),
                            ])
                        } else {
                            let connector = if *is_last { "\u{2514}\u{2500} " } else { "\u{251c}\u{2500} " };
                            ListItem::new(line![
                                connector.fg(theme.muted),
                                "\u{25cf} ".fg(theme.muted),
                                mac.fg(theme.foreground),
                                format!(" {}", dev).fg(theme.muted),
                            ])
                        }
                    }
                }).collect();
                let len = items.len();
                (items, len)
            }
            TAB_BOARDS => {
                let rows = board_rows(app);
                let items: Vec<ListItem> = rows.iter().map(|row| match row {
                    BoardRow::Group { vendor, count, expanded } => {
                        let chevron = if *expanded { "\u{25bc} " } else { "\u{25b6} " };
                        ListItem::new(line![
                            chevron.fg(theme.muted),
                            "\u{f0d4f} ".fg(theme.accent),
                            vendor.clone().fg(theme.foreground),
                            format!(" \u{b7} {}", count).fg(theme.muted),
                        ])
                    }
                    BoardRow::Leaf { board_idx, is_last } => {
                        let board = &app.workspace.boards[*board_idx];
                        let connector = if *is_last { "\u{2514}\u{2500} " } else { "\u{251c}\u{2500} " };
                        ListItem::new(line![
                            connector.fg(theme.muted),
                            "\u{f2db} ".fg(theme.muted),
                            board.name.clone().fg(theme.foreground),
                        ])
                    }
                }).collect();
                let len = items.len();
                (items, len)
            }
            _ => {
                let items: Vec<ListItem> = ECHO_ENTRIES.iter().map(|e| {
                    ListItem::new(line![
                        format!("{} ", e.icon).fg(theme.accent),
                        e.label.to_string().fg(theme.foreground),
                    ])
                }).collect();
                (items, ECHO_ENTRIES.len())
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
            TAB_PROBES => render_probes_detail(frame, area, app, idx),
            TAB_BOARDS  => render_boards_detail(frame, area, app, tab),
            _ => render_echo(frame, area, app),
        }
    }
}

fn ping_now(app: &mut App) {
    app.mcumgr.ping_async(app.frame_tick);
}

const BOARD_TABLE: &[(&str, &str)] = &[
    ("D0:CF:13:54:27:18", "walter/esp32s3/procpu"),
    ("8C:BF:EA:8E:AC:28", "xiao_esp32s3/esp32s3/procpu"),
];

fn board_for(mac: &str) -> Option<&'static str> {
    BOARD_TABLE.iter().find(|(m, _)| *m == mac).map(|(_, b)| *b)
}

fn probes_build(app: &mut App) {
    let rows = probe_rows(app);
    let idx  = app.state_of(PanelTag::Mcumgr).list.selected().unwrap_or(0);
    match rows.into_iter().nth(idx) {
        Some(ProbeRow::Leaf { probe_idx, .. }) => build_probe(app, probe_idx),
        Some(ProbeRow::Group { .. }) => {
            app.log_command("Build", "select a probe \u{2014} group row");
        }
        None => {}
    }
}

fn probes_enter(app: &mut App) {
    let rows = probe_rows(app);
    let idx  = app.state_of(PanelTag::Mcumgr).list.selected().unwrap_or(0);
    match rows.into_iter().nth(idx) {
        Some(ProbeRow::Group { key, .. }) => toggle_group_at_cursor(app, key, idx),
        Some(ProbeRow::Leaf { probe_idx, .. }) => monitor_probe(app, probe_idx),
        None => {}
    }
}

fn probes_flash(app: &mut App) {
    let rows = probe_rows(app);
    let idx  = app.state_of(PanelTag::Mcumgr).list.selected().unwrap_or(0);
    match rows.into_iter().nth(idx) {
        Some(ProbeRow::Leaf { probe_idx, .. }) => flash_probe(app, probe_idx),
        Some(ProbeRow::Group { .. }) => {
            app.log_command("Flash", "select a probe \u{2014} group row");
        }
        None => {}
    }
}

fn build_probe(app: &mut App, probe_idx: usize) {
    let Some(probe) = app.probe_list.get(probe_idx).cloned() else { return; };
    let Some(mac)   = probe.serial_number.clone() else {
        app.log_command("Build", "probe has no MAC \u{2014} cannot pick board");
        return;
    };
    let Some(board) = board_for(&mac) else {
        app.log_command("Build", format!("no board mapped for {mac} \u{2014} add to BOARD_TABLE"));
        return;
    };
    let label = format!("Build ({})", probe.identifier);
    let cmd   = format!("west build -b {board} -p");
    app.log_command(label.clone(), cmd.clone());
    app.active_command = Some(app.runner.spawn(label, cmd));
}

fn probes_toggle(app: &mut App) {
    let rows = probe_rows(app);
    let idx  = app.state_of(PanelTag::Mcumgr).list.selected().unwrap_or(0);
    let (key, group_idx) = match rows.iter().nth(idx) {
        Some(ProbeRow::Group { key, .. }) => (key.clone(), idx),
        Some(ProbeRow::Leaf { group_key, .. }) => {
            let g = rows.iter().position(|r| matches!(r, ProbeRow::Group { key: k, .. } if k == group_key));
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
    let Some(mac)  = probe.serial_number.clone() else {
        app.log_command(format!("Flash ({identifier})"), "probe has no MAC");
        return;
    };
    let label = format!("Flash ({identifier})");
    let cmd   = format!("west flash --esp-device hwgrep://{mac}");
    app.log_command(label.clone(), cmd.clone());
    app.active_command = Some(app.runner.spawn(label, cmd));
}

fn monitor_probe(app: &mut App, probe_idx: usize) {
    let Some(probe) = app.probe_list.get(probe_idx).cloned() else { return; };
    let identifier = probe.identifier;
    let Some(mac)  = probe.serial_number.clone() else {
        app.log_command(format!("Monitor ({identifier})"), "probe has no MAC");
        return;
    };
    let label = format!("Monitor ({identifier})");
    let cmd   = format!("west espressif monitor -p hwgrep://{mac}");
    app.log_command(label.clone(), cmd.clone());
    app.active_command = Some(app.runner.spawn(label, cmd));
}

fn probes_rescan(app: &mut App) {
    app.refresh_probes();
}

fn probes_toggle_view(app: &mut App) {
    app.probes_flat = !app.probes_flat;
    let state = app.state_of_mut(PanelTag::Mcumgr);
    state.list.select_first();
}

fn boards_toggle(app: &mut App) {
    let rows = board_rows(app);
    let idx  = app.state_of(PanelTag::Mcumgr).list.selected().unwrap_or(0);
    let vendor = match rows.iter().nth(idx) {
        Some(BoardRow::Group { vendor, .. }) => vendor.clone(),
        Some(BoardRow::Leaf { board_idx, .. }) => {
            let board = &app.workspace.boards[*board_idx];
            if board.vendor.is_empty() { "(unknown)".into() } else { board.vendor.clone() }
        }
        None => return,
    };
    if app.boards_collapsed_vendors.contains(&vendor) {
        app.boards_collapsed_vendors.remove(&vendor);
    } else {
        app.boards_collapsed_vendors.insert(vendor.clone());
    }
    let rows = board_rows(app);
    if let Some(pos) = rows.iter().position(|r| matches!(r, BoardRow::Group { vendor: v, .. } if *v == vendor)) {
        let state = app.state_of_mut(PanelTag::Mcumgr);
        state.list.list.select(Some(pos));
    }
}

fn render_boards_detail(frame: &mut Frame, area: Rect, app: &mut App, tab: &str) {
    let theme = *app.theme();
    let Some(board_idx) = selected_board_idx(app) else {
        frame.render_widget(Paragraph::new("select a board".fg(theme.label)), area);
        return;
    };
    let board = match app.workspace.boards.get(board_idx) {
        Some(b) => b.clone(),
        None    => return,
    };
    match tab {
        "Image" => {
            app.pinout_image.clone().render(frame, area, &board.name);
        }
        _ => {
            if board.name == "xiao_esp32s3" || board.name == "walter" || board.name == "walter_esp32s3" {
                devicetree::render(frame, area, app);
            } else {
                let lines = alloc::vec![
                    Line::from(board.name.clone().fg(theme.value).bold()),
                    Line::raw(""),
                    line![format!("{:<14}", "full name").fg(theme.label), board.full_name.fg(theme.value).bold()],
                    line![format!("{:<14}", "vendor").fg(theme.label),    board.vendor.fg(theme.value).bold()],
                    Line::raw(""),
                    Line::from("no pinout available for this board".fg(theme.label)),
                ];
                frame.render_widget(Paragraph::new(lines).wrap(Wrap { trim: false }), area);
            }
        }
    }
}

fn probes_in_group(app: &App, key: &str) -> Vec<usize> {
    let mut idxs: Vec<usize> = app.probe_list.iter().enumerate()
        .filter(|(_, p)| group_key_for(&p.identifier, p.vendor_id, p.product_id) == key)
        .map(|(i, _)| i)
        .collect();
    idxs.sort_by(|&a, &b| {
        let device_a = app.probe_list[a].device_path.as_deref();
        let device_b = app.probe_list[b].device_path.as_deref();
        device_a.is_none().cmp(&device_b.is_none()).then(device_a.cmp(&device_b))
    });
    idxs
}

fn render_probes_detail(frame: &mut Frame, area: Rect, app: &App, idx: usize) {
    let theme = *app.theme();
    let (probe_area, stream_area) = split_for_stream(area, app);
    let rows  = probe_rows(app);
    match rows.into_iter().nth(idx) {
        Some(ProbeRow::Group { label, vid, pid, count, key, .. }) => {
            let mut lines: Vec<Line<'static>> = Vec::new();
            let header = format!("{count} {} detected", if count == 1 { "probe" } else { "probes" });
            lines.push(Line::from(header.fg(theme.value).bold()));
            lines.push(Line::raw(""));
            if let Some(chip) = chip_family(vid, pid) {
                lines.push(kv(&theme, "target chip", chip.into()));
            }
            lines.push(kv(&theme, "descriptor", label));
            let vendor = vendor_name(vid).map(|n| format!("{:04x} ({n})", vid))
                                         .unwrap_or_else(|| format!("{:04x}", vid));
            lines.push(kv(&theme, "vendor", vendor));
            for (n, probe_idx) in probes_in_group(app, &key).into_iter().enumerate() {
                let probe  = &app.probe_list[probe_idx];
                let serial = probe.serial_number.clone().unwrap_or_else(|| "\u{2014}".into());
                let device = probe.device_path.clone().unwrap_or_else(|| "(no /dev match)".into());
                lines.push(Line::raw(""));
                lines.push(Line::from(format!("Probe {}", n + 1).fg(theme.value).bold()));
                lines.push(kv(&theme, "serial", serial));
                lines.push(kv(&theme, "device", device));
            }
            frame.render_widget(Paragraph::new(lines).wrap(Wrap { trim: false }), probe_area);
        }
        Some(ProbeRow::Leaf { probe_idx, .. }) => render_probe_leaf(frame, probe_area, app, probe_idx),
        None => {
            frame.render_widget(placeholder_paragraph(&theme, "no debug probe detected \u{2014} press r to rescan"), probe_area);
        }
    }
    if let Some(stream_area) = stream_area {
        render_stream(frame, stream_area, app);
    }
}

fn split_for_stream(area: Rect, app: &App) -> (Rect, Option<Rect>) {
    if app.active_command.is_none() { return (area, None); }
    let [top, bottom] = ratatui::layout::Layout::vertical([
        ratatui::layout::Constraint::Percentage(50),
        ratatui::layout::Constraint::Percentage(50),
    ]).areas(area);
    (top, Some(bottom))
}

fn render_stream(frame: &mut Frame, area: Rect, app: &App) {
    let theme = *app.theme();
    let Some(stream) = app.active_command.as_ref() else { return; };
    let status = stream.status();
    let (status_label, status_color) = match status {
        crate::commands::runner::StreamStatus::Running    => ("running\u{2026}", theme.warning),
        crate::commands::runner::StreamStatus::Exited(0)  => ("exited \u{b7} ok", theme.success),
        crate::commands::runner::StreamStatus::Exited(c)  => return render_stream_with_code(frame, area, app, c, "exited"),
        crate::commands::runner::StreamStatus::Killed     => ("killed", theme.muted),
    };
    render_stream_body(frame, area, &theme, stream.label(), status_label, status_color, stream.snapshot());
}

fn render_stream_with_code(frame: &mut Frame, area: Rect, app: &App, code: i32, verb: &str) {
    let theme = *app.theme();
    let Some(stream) = app.active_command.as_ref() else { return; };
    let label  = stream.label();
    let status = format!("{verb} \u{b7} code {code}");
    let color  = if code == 0 { theme.success } else { theme.warning };
    render_stream_body(frame, area, &theme, label, &status, color, stream.snapshot());
}

fn render_stream_body(frame: &mut Frame, area: Rect, theme: &Theme, label: &str, status: &str, status_color: ratatui::style::Color, snapshot: Vec<String>) {
    let header = ratatui::macros::line![
        label.to_string().fg(theme.value),
        "  \u{25cf} ".fg(status_color),
        status.to_string().fg(status_color),
    ];
    let visible_rows = area.height.saturating_sub(2).max(1) as usize;
    let tail_start   = snapshot.len().saturating_sub(visible_rows);
    let mut lines: Vec<Line<'static>> = Vec::with_capacity(visible_rows + 2);
    lines.push(header);
    lines.push(Line::raw(""));
    for line in snapshot.iter().skip(tail_start) {
        lines.push(Line::from(line.clone().fg(theme.foreground)));
    }
    frame.render_widget(Paragraph::new(lines).wrap(Wrap { trim: false }), area);
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
