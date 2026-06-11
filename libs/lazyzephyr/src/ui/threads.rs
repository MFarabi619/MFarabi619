use alloc::{format, string::{String, ToString}, vec, vec::Vec};

use ratatui::{
    Frame,
    layout::{Constraint, Layout, Rect},
    style::{Style, Stylize},
    text::{Line, Span},
    widgets::{Block, Gauge, List, ListItem, Paragraph, Wrap},
};

use crate::{
    app::App,
    panel::{Panel, PanelTag},
    ui::widgets::{
        kv, panel_title_tabbed, placeholder_paragraph, render_conf_directives,
        selection_style, selection_symbol, titled_list_block,
    },
};

const TABS: &[&str] = &["Devices", "Threads"];
const TAB_DEVICES: usize = 0;
const TAB_THREADS: usize = 1;

struct MockDevice {
    name:      &'static str,
    state:     &'static str,
    dt_labels: Option<&'static str>,
}

// TODO: send `device list` to the Zephyr shell and parse the response.
const MOCK_DEVICES: &[MockDevice] = &[
    MockDevice { name: "clock",                    state: "READY", dt_labels: Some("clock") },
    MockDevice { name: "gpio@60004800",            state: "READY", dt_labels: Some("gpio1") },
    MockDevice { name: "gpio@60004000",            state: "READY", dt_labels: Some("gpio0") },
    MockDevice { name: "trng@6003507c",            state: "READY", dt_labels: Some("trng0") },
    MockDevice { name: "uart@60038000",            state: "READY", dt_labels: Some("usb_serial") },
    MockDevice { name: "uart@60000000",            state: "READY", dt_labels: Some("uart0 xiao_serial") },
    MockDevice { name: "WIREGUARD0",               state: "READY", dt_labels: None },
    MockDevice { name: "WIREGUARD_CTRL",           state: "READY", dt_labels: None },
    MockDevice { name: "flash-controller@60002000", state: "READY", dt_labels: Some("flash") },
    MockDevice { name: "wifi",                     state: "READY", dt_labels: Some("wifi") },
];

pub struct ThreadsPanel;

impl Panel for ThreadsPanel {
    fn tag(&self) -> PanelTag { PanelTag::Threads }
    fn label(&self) -> &'static str { "Kernel" }
    fn inner_tabs(&self) -> &'static [&'static str] { TABS }

    fn detail_tabs(&self, app: &App) -> Vec<&'static str> {
        match app.state_of(self.tag()).list_tab {
            TAB_DEVICES => vec!["Info", "Conf"],
            _ => vec!["Logs", "Stats", "Conf"],
        }
    }

    fn supports_filter(&self) -> bool { true }

    fn footer_actions(&self, _app: &App) -> alloc::vec::Vec<crate::panel::FooterAction> {
        alloc::vec![("Filter", "/")]
    }

    fn list_len(&self, app: &App) -> usize {
        matching_indices(app).len()
    }

    fn current_name(&self, app: &App) -> String {
        let matches = matching_indices(app);
        let state = app.state_of(self.tag());
        let idx = state.list.selected().unwrap_or(0);
        let entry_idx = matches.get(idx).copied().unwrap_or(0);
        match state.list_tab {
            TAB_THREADS => app.source.threads().get(entry_idx).map(|t| t.name.clone()).unwrap_or_default(),
            TAB_DEVICES => MOCK_DEVICES.get(entry_idx).map(|d| d.name.into()).unwrap_or_default(),
            _           => String::new(),
        }
    }

    fn render_list(&self, frame: &mut Frame, area: Rect, app: &mut App, focused: bool) {
        let theme  = *app.theme();
        let state  = app.state_of(self.tag());
        let active = state.list_tab;
        let selected = state.list.selected();
        let title = panel_title_tabbed(
            &theme,
            app.index_of(self.tag()) + 1,
            TABS,
            active,
            focused,
            None,
        );
        let total = self.list_len(app);
        let block = titled_list_block(&theme, title, focused, selected, total);

        let matches = matching_indices(app);
        let items: Vec<ListItem> = match active {
            TAB_THREADS => matches.iter()
                .filter_map(|i| app.source.threads().get(*i))
                .map(|thread| {
                    let ratio = thread.stack_ratio();
                    let color = theme.tier_for_ratio(ratio);
                    ListItem::new(Line::from(vec![
                        Span::raw(format!("{:<18}", thread.name)).fg(theme.value).bold(),
                        Span::raw(format!("{:>3}%", (ratio * 100.0) as u32)).fg(color).bold(),
                        Span::raw(format!("  p{}", thread.priority)).fg(theme.label),
                    ]))
                }).collect(),
            TAB_DEVICES => {
                let max_label_width = MOCK_DEVICES.iter()
                    .filter_map(|d| d.dt_labels)
                    .map(primary_dt_label)
                    .map(str::len)
                    .max()
                    .unwrap_or(0);
                matches.iter()
                    .filter_map(|i| MOCK_DEVICES.get(*i))
                    .map(|device| {
                        let dot_color = match device.state {
                            "READY"    => theme.success,
                            "DISABLED" => theme.label,
                            _          => theme.warning,
                        };
                        let label = device.dt_labels.map(primary_dt_label).unwrap_or("");
                        ListItem::new(Line::from(vec![
                            Span::raw("●").fg(dot_color),
                            Span::raw(" "),
                            Span::raw(format!("{:<w$}", label, w = max_label_width)).fg(theme.value).bold(),
                            Span::raw("  ").fg(theme.label),
                            Span::raw(device.name.to_string()).fg(theme.foreground),
                        ]))
                    }).collect()
            }
            _ => Vec::new(),
        };

        let list = List::new(items).block(block)
            .highlight_style(selection_style(&theme, focused))
            .highlight_symbol(selection_symbol(focused));
        let state = &mut app.state_of_mut(self.tag()).list.state;
        frame.render_stateful_widget(list, area, state);
    }

    fn render_detail(&self, frame: &mut Frame, area: Rect, app: &mut App, tab: &str) {
        let active_tab = app.state_of(self.tag()).list_tab;
        match active_tab {
            TAB_THREADS => match tab {
                "Stats" => render_thread_stats(frame, area, app),
                "Conf"  => render_thread_conf (frame, area, app),
                _       => render_thread_logs (frame, area, app),
            },
            TAB_DEVICES => match tab {
                "Conf" => render_device_conf(frame, area, app),
                _      => render_device_info(frame, area, app),
            },
            _ => {}
        }
    }
}

fn primary_dt_label(labels: &str) -> &str {
    labels.split_whitespace().next().unwrap_or("")
}

fn matching_indices(app: &App) -> Vec<usize> {
    let state  = app.state_of(PanelTag::Threads);
    let needle = state.filter.to_lowercase();
    match state.list_tab {
        TAB_THREADS => app.source.threads().iter().enumerate()
            .filter(|(_, t)| needle.is_empty() || t.name.to_lowercase().contains(&needle))
            .map(|(i, _)| i).collect(),
        TAB_DEVICES => MOCK_DEVICES.iter().enumerate()
            .filter(|(_, d)| {
                if needle.is_empty() { return true; }
                d.name.to_lowercase().contains(&needle)
                    || d.dt_labels.map_or(false, |l| l.to_lowercase().contains(&needle))
            })
            .map(|(i, _)| i).collect(),
        _ => Vec::new(),
    }
}

fn selected_entry_index(app: &App) -> Option<usize> {
    let matches = matching_indices(app);
    let pos = app.state_of(PanelTag::Threads).list.selected().unwrap_or(0);
    matches.get(pos).copied()
}

fn render_thread_logs(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = *app.theme();
    let Some(idx) = selected_entry_index(app) else {
        frame.render_widget(placeholder_paragraph(&theme, "no thread selected"), area);
        return;
    };
    let Some(thread) = app.source.threads().get(idx) else {
        frame.render_widget(placeholder_paragraph(&theme, "no thread selected"), area);
        return;
    };
    let rows = vec![
        kv(&theme, "state",       thread.state.clone()),
        kv(&theme, "stack used",  format!("{} B", thread.stack_used)),
        kv(&theme, "stack total", format!("{} B", thread.stack_size)),
        kv(&theme, "headroom",    format!("{} B", thread.stack_size.saturating_sub(thread.stack_used))),
    ];
    frame.render_widget(Paragraph::new(rows).wrap(Wrap { trim: false }), area);
}

fn render_thread_stats(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = *app.theme();
    let Some(idx) = selected_entry_index(app) else {
        frame.render_widget(placeholder_paragraph(&theme, "no thread selected"), area);
        return;
    };
    let Some(thread) = app.source.threads().get(idx) else {
        frame.render_widget(placeholder_paragraph(&theme, "no thread selected"), area);
        return;
    };
    let ratio = thread.stack_ratio();
    let color = theme.tier_for_ratio(ratio);
    let [_g, gauge_area, _g2] = Layout::vertical([
        Constraint::Length(1), Constraint::Length(3), Constraint::Min(0),
    ]).areas(area);
    let gauge = Gauge::default()
        .ratio(ratio.min(1.0))
        .gauge_style(Style::new().fg(color).bg(theme.selection_background))
        .label(Span::raw(format!("{} / {} B   ({:.1}%)", thread.stack_used, thread.stack_size, ratio * 100.0))
            .fg(theme.selection_foreground).bold())
        .block(Block::new());
    frame.render_widget(gauge, gauge_area);
}

fn render_thread_conf(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = *app.theme();
    // TODO: parse libs/firmware/**/*.conf instead of hardcoding
    render_conf_directives(frame, area, &theme, &[
        "CONFIG_MULTITHREADING=y",
        "CONFIG_NUM_PREEMPT_PRIORITIES=15",
        "CONFIG_NUM_COOP_PRIORITIES=16",
        "CONFIG_MAIN_STACK_SIZE=4096",
        "CONFIG_SYSTEM_WORKQUEUE_STACK_SIZE=2048",
        "CONFIG_THREAD_NAME=y",
        "CONFIG_THREAD_STACK_INFO=y",
        "CONFIG_THREAD_MONITOR=y",
        "CONFIG_THREAD_RUNTIME_STATS=y",
        "CONFIG_SCHED_THREAD_USAGE=y",
    ]);
}

fn render_device_info(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = *app.theme();
    let Some(idx) = selected_entry_index(app) else {
        frame.render_widget(placeholder_paragraph(&theme, "no device selected"), area);
        return;
    };
    let Some(device) = MOCK_DEVICES.get(idx) else {
        frame.render_widget(placeholder_paragraph(&theme, "no device selected"), area);
        return;
    };
    let mut rows = vec![
        kv(&theme, "name",  device.name.to_string()),
        kv(&theme, "state", device.state.to_string()),
    ];
    if let Some(labels) = device.dt_labels {
        rows.push(kv(&theme, "dt labels", labels.to_string()));
    }
    frame.render_widget(Paragraph::new(rows).wrap(Wrap { trim: false }), area);
}

fn render_device_conf(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = *app.theme();
    // TODO: parse libs/firmware/**/*.conf instead of hardcoding
    render_conf_directives(frame, area, &theme, &[
        "CONFIG_DEVICE_DEPS=y",
        "CONFIG_DEVICE_DT_METADATA=y",
        "CONFIG_DEVICE_SHELL=y",
    ]);
}
