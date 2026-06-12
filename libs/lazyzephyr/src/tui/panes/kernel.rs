use alloc::{format, string::{String, ToString}, vec, vec::Vec};

use ratatui::{
    Frame,
    layout::Rect,
    macros::{line, vertical},
    style::{Style, Stylize},
    text::{Line, Span},
    widgets::{Block, Gauge, List, ListItem, Paragraph, Wrap},
};

use crate::{
    commands::source::{HeapPoolEntry, ThreadEntry},
    tui::{
        matcher::Matcher,
        panel::{Panel, PanelTag},
        popup_chrome::highlight_line,
        render::{
            kv, overlay_panel_tabs, placeholder_paragraph, render_conf_directives,
            selection_style, selection_symbol, titled_list_block,
        },
        state::App,
    },
};

const TABS: &[&str] = &["Heap pools", "Devices", "Threads"];
const TAB_HEAP_POOLS: usize = 0;
const TAB_DEVICES:    usize = 1;
const TAB_THREADS:    usize = 2;

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

pub struct KernelPanel;

impl Panel for KernelPanel {
    fn tag(&self) -> PanelTag { PanelTag::Kernel }
    fn label(&self) -> &'static str { "Kernel" }
    fn inner_tabs(&self) -> &'static [&'static str] { TABS }

    fn detail_tabs(&self, app: &App) -> Vec<&'static str> {
        match app.state_of(self.tag()).list_tab {
            TAB_HEAP_POOLS => vec!["Logs", "Stats", "Conf"],
            TAB_DEVICES    => vec!["Info", "Conf"],
            _              => vec!["Logs", "Stats", "Conf"],
        }
    }

    fn bindings(&self, _app: &App) -> alloc::vec::Vec<crate::tui::keybindings::Binding> {
        use crate::tui::keybindings::{ACTION_TAG, Binding, enter_search};
        alloc::vec![
            Binding::new(&["/"], "filter list").footer().short("Filter").tag(ACTION_TAG).handler(enter_search),
        ]
    }

    fn list_len(&self, app: &App) -> usize {
        let m: &dyn Matcher = &*app.matcher;
        let state = app.state_of(self.tag());
        match state.list_tab {
            TAB_HEAP_POOLS => state.list.view(app.source.heap_pools(), |t, n| heap_score(t, n, m)).len(),
            TAB_DEVICES    => state.list.view(MOCK_DEVICES, |d, n| device_score(d, n, m)).len(),
            TAB_THREADS    => state.list.view(app.source.threads(), |t, n| thread_score(t, n, m)).len(),
            _              => 0,
        }
    }

    fn current_name(&self, app: &App) -> String {
        let m: &dyn Matcher = &*app.matcher;
        let state = app.state_of(self.tag());
        match state.list_tab {
            TAB_HEAP_POOLS => state.list.view(app.source.heap_pools(), |t, n| heap_score(t, n, m))
                .selected().map(|p| p.name.clone()).unwrap_or_default(),
            TAB_DEVICES    => state.list.view(MOCK_DEVICES, |d, n| device_score(d, n, m))
                .selected().map(|d| d.name.into()).unwrap_or_default(),
            TAB_THREADS    => state.list.view(app.source.threads(), |t, n| thread_score(t, n, m))
                .selected().map(|t| t.name.clone()).unwrap_or_default(),
            _              => String::new(),
        }
    }

    fn render_list(&self, frame: &mut Frame, area: Rect, app: &mut App, focused: bool) {
        let theme    = *app.theme();
        let state    = app.state_of(self.tag());
        let active   = state.list_tab;
        let selected = state.list.selected();
        let panel_idx = app.index_of(self.tag()) + 1;
        let show_jumps = app.config.gui.show_panel_jumps;
        let m: &dyn Matcher = &*app.matcher;
        let filter = state.list.filter.clone();

        let (total, items): (usize, Vec<ListItem>) = match active {
            TAB_HEAP_POOLS => {
                let view = state.list.view(app.source.heap_pools(), |t, n| heap_score(t, n, m));
                let total = view.len();
                let base = Style::new().fg(theme.foreground);
                let hl   = Style::new().fg(theme.accent).underlined();
                let items: Vec<ListItem> = view.iter().map(|(_, pool)| {
                    let ratio = pool.usage_ratio();
                    let color = theme.tier_for_ratio(ratio);
                    let indices = if filter.is_empty() { Vec::new() }
                                  else { m.highlight_indices(&pool.name, &filter).unwrap_or_default() };
                    let mut spans = highlight_line(&pool.name, &indices, base, hl).spans;
                    let pad = 18_usize.saturating_sub(pool.name.chars().count());
                    if pad > 0 { spans.push(Span::styled(" ".repeat(pad), base)); }
                    spans.push(Span::styled(format!("{:>3}%", (ratio * 100.0) as u32), Style::new().fg(color)));
                    spans.push(Span::styled(format!("  {}/{}", pool.used_blocks(), pool.total_blocks), Style::new().fg(theme.muted)));
                    ListItem::new(Line::from(spans))
                }).collect();
                (total, items)
            }
            TAB_THREADS => {
                let view = state.list.view(app.source.threads(), |t, n| thread_score(t, n, m));
                let total = view.len();
                let items: Vec<ListItem> = view.iter().map(|(_, thread)| {
                    let ratio = thread.stack_ratio();
                    let color = theme.tier_for_ratio(ratio);
                    ListItem::new(line![
                        format!("{:<18}", thread.name).fg(theme.foreground),
                        format!("{:>3}%", (ratio * 100.0) as u32).fg(color),
                        format!("  p{}", thread.priority).fg(theme.muted),
                    ])
                }).collect();
                (total, items)
            }
            TAB_DEVICES => {
                let view = state.list.view(MOCK_DEVICES, |d, n| device_score(d, n, m));
                let total = view.len();
                let max_label_width = MOCK_DEVICES.iter()
                    .filter_map(|d| d.dt_labels)
                    .map(primary_dt_label)
                    .map(str::len)
                    .max()
                    .unwrap_or(0);
                let items: Vec<ListItem> = view.iter().map(|(_, device)| {
                    let dot_color = match device.state {
                        "READY"    => theme.success,
                        "DISABLED" => theme.label,
                        _          => theme.warning,
                    };
                    let label = device.dt_labels.map(primary_dt_label).unwrap_or("");
                    ListItem::new(line![
                        "●".fg(dot_color),
                        " ",
                        format!("{:<w$}", label, w = max_label_width).fg(theme.foreground),
                        "  ".fg(theme.muted),
                        device.name.to_string().fg(theme.muted),
                    ])
                }).collect();
                (total, items)
            }
            _ => (0, Vec::new()),
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
        let active_tab = app.state_of(self.tag()).list_tab;
        match active_tab {
            TAB_HEAP_POOLS => match tab {
                "Stats" => render_pool_stats(frame, area, app),
                "Conf"  => render_pool_conf(frame, area, app),
                _       => render_pool_logs(frame, area, app),
            },
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

fn thread_score(t: &ThreadEntry, needle: &str, m: &dyn Matcher) -> Option<i64> {
    m.match_score(&t.name, needle)
}

fn device_score(d: &MockDevice, needle: &str, m: &dyn Matcher) -> Option<i64> {
    let name = m.match_score(d.name, needle);
    let labels = d.dt_labels.and_then(|l| m.match_score(l, needle));
    [name, labels].into_iter().flatten().max()
}

fn heap_score(p: &HeapPoolEntry, needle: &str, m: &dyn Matcher) -> Option<i64> {
    m.match_score(&p.name, needle)
}

fn selected_thread<'a>(app: &'a App) -> Option<&'a ThreadEntry> {
    let m: &dyn Matcher = &*app.matcher;
    app.state_of(PanelTag::Kernel).list
        .view(app.source.threads(), |t, n| thread_score(t, n, m))
        .selected()
}

fn selected_device<'a>(app: &'a App) -> Option<&'a MockDevice> {
    let m: &dyn Matcher = &*app.matcher;
    app.state_of(PanelTag::Kernel).list
        .view(MOCK_DEVICES, |d, n| device_score(d, n, m))
        .selected()
}

fn selected_pool<'a>(app: &'a App) -> Option<&'a HeapPoolEntry> {
    let m: &dyn Matcher = &*app.matcher;
    app.state_of(PanelTag::Kernel).list
        .view(app.source.heap_pools(), |t, n| heap_score(t, n, m))
        .selected()
}

fn render_thread_logs(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = *app.theme();
    let Some(thread) = selected_thread(app) else {
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
    let Some(thread) = selected_thread(app) else {
        frame.render_widget(placeholder_paragraph(&theme, "no thread selected"), area);
        return;
    };
    let ratio = thread.stack_ratio();
    let color = theme.tier_for_ratio(ratio);
    let [_g, gauge_area, _g2] = vertical![==1, ==3, *=1].areas(area);
    let label = format!("{} / {} B   ({:.1}%)", thread.stack_used, thread.stack_size, ratio * 100.0);
    let gauge = Gauge::default()
        .ratio(ratio.min(1.0))
        .gauge_style(Style::new().fg(color).bg(theme.selection_background))
        .label(label.fg(theme.selection_foreground).bold())
        .block(Block::new());
    frame.render_widget(gauge, gauge_area);
}

fn render_thread_conf(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = *app.theme();
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
    let Some(device) = selected_device(app) else {
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
    render_conf_directives(frame, area, &theme, &[
        "CONFIG_DEVICE_DEPS=y",
        "CONFIG_DEVICE_DT_METADATA=y",
        "CONFIG_DEVICE_SHELL=y",
    ]);
}

fn render_pool_logs(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = *app.theme();
    let Some(pool) = selected_pool(app) else {
        frame.render_widget(placeholder_paragraph(&theme, "no pool selected"), area);
        return;
    };
    let rows = vec![
        kv(&theme, "name",         pool.name.clone()),
        kv(&theme, "block size",   format!("{} B", pool.block_size)),
        kv(&theme, "total blocks", format!("{}", pool.total_blocks)),
        kv(&theme, "free blocks",  format!("{}", pool.free_blocks)),
        kv(&theme, "used blocks",  format!("{}", pool.used_blocks())),
        kv(&theme, "min free",     format!("{}", pool.min_free)),
    ];
    frame.render_widget(Paragraph::new(rows).wrap(Wrap { trim: false }), area);
}

fn render_pool_stats(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = *app.theme();
    let Some(pool) = selected_pool(app) else {
        frame.render_widget(placeholder_paragraph(&theme, "no heap pool selected"), area);
        return;
    };
    let ratio = pool.usage_ratio();
    let watermark = pool.watermark_ratio();
    let color = theme.tier_for_ratio(ratio);
    let watermark_color = theme.tier_for_ratio(watermark);

    let [_g0, u_label, u_gauge, _g1, w_label, w_gauge, _g2] =
        vertical![==1, ==1, ==3, ==1, ==1, ==3, *=1].areas(area);

    frame.render_widget(Paragraph::new(Line::from(" current usage ".fg(theme.label))), u_label);
    let u_text = format!("{}/{} blk · {:.1}%", pool.used_blocks(), pool.total_blocks, ratio * 100.0);
    frame.render_widget(
        Gauge::default()
            .ratio(ratio.min(1.0))
            .gauge_style(Style::new().fg(color).bg(theme.selection_background))
            .label(u_text.fg(theme.selection_foreground).bold())
            .block(Block::new()),
        u_gauge,
    );
    frame.render_widget(Paragraph::new(Line::from(" peak watermark (min free) ".fg(theme.label))), w_label);
    let w_text = format!("min free {} blk · {:.1}% peak", pool.min_free, watermark * 100.0);
    frame.render_widget(
        Gauge::default()
            .ratio(watermark.min(1.0))
            .gauge_style(Style::new().fg(watermark_color).bg(theme.selection_background))
            .label(w_text.fg(theme.selection_foreground).bold())
            .block(Block::new()),
        w_gauge,
    );
}

fn render_pool_conf(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = *app.theme();
    render_conf_directives(frame, area, &theme, &[
        "CONFIG_HEAP_MEM_POOL_SIZE=49152",
        "CONFIG_KERNEL_MEM_POOL=y",
        "CONFIG_NET_BUF_POOL_USAGE=y",
        "CONFIG_MEM_SLAB_TRACE_MAX_UTILIZATION=y",
        "CONFIG_SYS_HEAP_RUNTIME_STATS=y",
    ]);
}
