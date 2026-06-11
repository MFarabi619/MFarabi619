use alloc::{format, string::String, vec, vec::Vec};

use ratatui::{
    Frame,
    layout::{Constraint, Layout, Rect},
    style::{Style, Stylize},
    text::{Line, Span},
    widgets::{Bar, BarChart, BarGroup, Block, Cell, Gauge, List, ListItem, Paragraph, Row, Table, Wrap},
};

use crate::{
    app::App,
    panel::{Panel, PanelTag},
    ui::widgets::{
        kv, panel_title_tabbed, placeholder_paragraph, render_conf_directives,
        selection_style, selection_symbol, titled_list_block,
    },
};

const TABS: &[&str] = &["Interfaces", "Stats"];
const TAB_INTERFACES: usize = 0;
const TAB_STATS:      usize = 1;

pub struct NetworkPanel;

impl Panel for NetworkPanel {
    fn tag(&self) -> PanelTag { PanelTag::Network }
    fn label(&self) -> &'static str { "Network" }
    fn detail_tabs(&self, _app: &App) -> Vec<&'static str> { vec!["Logs", "Stats", "Conf"] }
    fn inner_tabs(&self) -> &'static [&'static str] { TABS }

    fn supports_filter(&self) -> bool { true }

    fn footer_actions(&self, app: &App) -> alloc::vec::Vec<crate::panel::FooterAction> {
        match app.state_of(self.tag()).list_tab {
            // TODO: wire `p` to send `net ping` and `u`/`d` to bring iface up/down.
            TAB_INTERFACES => alloc::vec![("Ping", "p"), ("Up", "u"), ("Down", "d"), ("Filter", "/")],
            // TODO: wire `r` to send `stats reset` to the shell.
            TAB_STATS      => alloc::vec![("Reset", "r"), ("Filter", "/")],
            _              => alloc::vec::Vec::new(),
        }
    }

    fn list_len(&self, app: &App) -> usize { matching_indices(app).len() }

    fn current_name(&self, app: &App) -> String {
        let state = app.state_of(self.tag());
        let entry_idx = selected_entry_index(app).unwrap_or(0);
        match state.list_tab {
            TAB_INTERFACES => app.source.interfaces().get(entry_idx).map(|i| i.name.clone()).unwrap_or_default(),
            TAB_STATS      => app.source.stat_groups().get(entry_idx).map(|g| g.name.clone()).unwrap_or_default(),
            _              => String::new(),
        }
    }

    fn render_list(&self, frame: &mut Frame, area: Rect, app: &mut App, focused: bool) {
        let theme = *app.theme();
        let state = app.state_of(self.tag());
        let active_tab = state.list_tab;
        let selected = state.list.selected();
        let title = panel_title_tabbed(
            &theme,
            app.index_of(self.tag()) + 1,
            TABS,
            active_tab,
            focused,
            None,
        );
        let total = self.list_len(app);
        let block = titled_list_block(&theme, title, focused, selected, total);

        let matches = matching_indices(app);
        let items: Vec<ListItem> = match active_tab {
            TAB_INTERFACES => matches.iter().filter_map(|i| app.source.interfaces().get(*i)).map(|iface| {
                let status_color = if iface.up { theme.success } else { theme.label };
                ListItem::new(Line::from(vec![
                    Span::raw(format!("{} ", iface.kind.icon())).fg(status_color).bold(),
                    Span::raw(format!("{:<10}", iface.name)).fg(theme.value).bold(),
                    Span::raw(format!("{:<10}", iface.kind.label())).fg(theme.label),
                    Span::raw(if iface.ipv4_addr.is_empty() { "(down)".into() } else { iface.ipv4_addr.clone() }).fg(theme.label),
                ]))
            }).collect(),
            TAB_STATS => matches.iter().filter_map(|i| app.source.stat_groups().get(*i)).map(|group| {
                ListItem::new(Line::from(vec![
                    Span::raw(format!("{:<22}", group.name)).fg(theme.value).bold(),
                    Span::raw(format!("{} field", group.fields.len())).fg(theme.label),
                ]))
            }).collect(),
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
        match (active_tab, tab) {
            (TAB_INTERFACES, "Stats") => render_iface_stats(frame, area, app),
            (TAB_INTERFACES, "Conf")  => render_iface_conf (frame, area, app),
            (TAB_INTERFACES, _)       => render_iface_logs (frame, area, app),
            (TAB_STATS,      "Stats") => render_stat_stats (frame, area, app),
            (TAB_STATS,      "Conf")  => render_stat_conf  (frame, area, app),
            (TAB_STATS,      _)       => render_stat_logs  (frame, area, app),
            _ => {}
        }
    }
}

fn matching_indices(app: &App) -> Vec<usize> {
    let state = app.state_of(PanelTag::Network);
    let needle = state.filter.to_lowercase();
    match state.list_tab {
        TAB_INTERFACES => app.source.interfaces().iter().enumerate()
            .filter(|(_, i)| needle.is_empty()
                || i.name.to_lowercase().contains(&needle)
                || i.kind.label().to_lowercase().contains(&needle)
                || i.ipv4_addr.to_lowercase().contains(&needle))
            .map(|(i, _)| i).collect(),
        TAB_STATS => app.source.stat_groups().iter().enumerate()
            .filter(|(_, g)| needle.is_empty() || g.name.to_lowercase().contains(&needle))
            .map(|(i, _)| i).collect(),
        _ => Vec::new(),
    }
}

fn selected_entry_index(app: &App) -> Option<usize> {
    let matches = matching_indices(app);
    let pos = app.state_of(PanelTag::Network).list.selected().unwrap_or(0);
    matches.get(pos).copied()
}

fn render_iface_logs(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = *app.theme();
    let Some(iface) = selected_entry_index(app).and_then(|i| app.source.interfaces().get(i)) else {
        frame.render_widget(placeholder_paragraph(&theme, "no interface selected"), area);
        return;
    };
    let mut rows = vec![
        kv(&theme, "name",      iface.name.clone()),
        kv(&theme, "kind",      iface.kind.label().into()),
        kv(&theme, "up",        if iface.up { "yes".into() } else { "no".into() }),
        kv(&theme, "link addr", iface.link_addr.clone()),
        kv(&theme, "mtu",       format!("{}", iface.mtu)),
        kv(&theme, "flags",     iface.flags.clone()),
        kv(&theme, "status",    iface.status.clone()),
        kv(&theme, "ipv4 addr", iface.ipv4_addr.clone()),
        kv(&theme, "gateway",   iface.ipv4_gateway.clone()),
    ];
    if let Some(dhcp) = &iface.dhcp_state { rows.push(kv(&theme, "dhcp", dhcp.clone())); }
    if let Some(vname) = &iface.virtual_name { rows.push(kv(&theme, "virtual name", vname.clone())); }
    if let Some(pk) = &iface.public_key { rows.push(kv(&theme, "public key", pk.clone())); }
    if let Some(wifi) = &iface.wifi {
        rows.push(kv(&theme, "ssid",       wifi.ssid.clone()));
        rows.push(kv(&theme, "bssid",      wifi.bssid.clone()));
        rows.push(kv(&theme, "band",       wifi.band.clone()));
        rows.push(kv(&theme, "channel",    format!("{}", wifi.channel)));
        rows.push(kv(&theme, "security",   wifi.security.clone()));
        rows.push(kv(&theme, "link mode",  wifi.link_mode.clone()));
        rows.push(kv(&theme, "rssi",       format!("{} dBm", wifi.rssi)));
        rows.push(kv(&theme, "wifi state", wifi.state.clone()));
    }
    frame.render_widget(Paragraph::new(rows).wrap(Wrap { trim: false }), area);
}

fn render_iface_stats(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = *app.theme();
    let Some(iface) = selected_entry_index(app).and_then(|i| app.source.interfaces().get(i)) else {
        frame.render_widget(placeholder_paragraph(&theme, "no interface selected"), area);
        return;
    };
    let Some(wifi) = &iface.wifi else {
        frame.render_widget(placeholder_paragraph(&theme, "no stats for non-wifi interface yet"), area);
        return;
    };
    let ratio = wifi.rssi_ratio();
    let color = wifi.rssi_color(&theme);
    let [_g, gauge_area, _g2] = Layout::vertical([
        Constraint::Length(1), Constraint::Length(3), Constraint::Min(0),
    ]).areas(area);
    let gauge = Gauge::default()
        .ratio(ratio.min(1.0))
        .gauge_style(Style::new().fg(color).bg(theme.selection_background))
        .label(Span::raw(format!("RSSI {} dBm  ({:.0}%)", wifi.rssi, ratio * 100.0))
            .fg(theme.selection_foreground).bold())
        .block(Block::new());
    frame.render_widget(gauge, gauge_area);
}

fn render_iface_conf(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = *app.theme();
    // TODO: parse libs/firmware/networking/**/*.conf instead of hardcoding
    render_conf_directives(frame, area, &theme, &[
        "CONFIG_NETWORKING=y",
        "CONFIG_NET_IPV4=y",
        "CONFIG_NET_DHCPV4=y",
        "CONFIG_NET_WIFI=y",
        "CONFIG_WIFI_NM=y",
        "CONFIG_WIREGUARD=y",
        "CONFIG_NET_TC_THREAD_PREEMPTIVE=y",
        "CONFIG_NET_PKT_RX_COUNT=24",
        "CONFIG_NET_PKT_TX_COUNT=24",
        "CONFIG_NET_BUF_RX_COUNT=72",
        "CONFIG_NET_BUF_TX_COUNT=72",
    ]);
}

fn render_stat_logs(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = *app.theme();
    let Some(group) = selected_entry_index(app).and_then(|i| app.source.stat_groups().get(i)) else {
        frame.render_widget(placeholder_paragraph(&theme, "no stat group selected"), area);
        return;
    };
    if group.fields.is_empty() {
        frame.render_widget(placeholder_paragraph(&theme, "stat group has no fields"), area);
        return;
    }
    let rows: Vec<Row<'static>> = group.fields.iter().map(|(field, value)| {
        Row::new(vec![
            Cell::from(Span::raw(field.clone()).fg(theme.value).bold()),
            Cell::from(Span::raw(format!("{value}")).fg(theme.label)),
        ])
    }).collect();
    let table = Table::new(rows, [Constraint::Percentage(60), Constraint::Percentage(40)])
        .header(Row::new(vec![
            Cell::from(Span::raw(" field").fg(theme.accent).bold()),
            Cell::from(Span::raw(" value").fg(theme.accent).bold()),
        ]))
        .column_spacing(2);
    frame.render_widget(table, area);
}

fn render_stat_stats(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = *app.theme();
    let Some(group) = selected_entry_index(app).and_then(|i| app.source.stat_groups().get(i)) else {
        frame.render_widget(placeholder_paragraph(&theme, "no stat group selected"), area);
        return;
    };
    if group.fields.is_empty() {
        frame.render_widget(placeholder_paragraph(&theme, "stat group has no fields"), area);
        return;
    }
    let max = group.fields.iter().map(|(_, v)| *v).max().unwrap_or(1).max(1);
    let bars: Vec<Bar> = group.fields.iter().map(|(name, value)| {
        Bar::default()
            .value(*value)
            .label(Line::from(name.clone()))
            .text_value(format!("{value}"))
            .style(Style::new().fg(theme.accent))
    }).collect();
    let chart = BarChart::default()
        .data(BarGroup::default().bars(&bars))
        .bar_width(9)
        .bar_gap(2)
        .max(max)
        .label_style(Style::new().fg(theme.label))
        .value_style(Style::new().fg(theme.selection_foreground).bold());
    let [hdr, body] = Layout::vertical([Constraint::Length(1), Constraint::Min(0)]).areas(area);
    frame.render_widget(
        Paragraph::new(Line::from(Span::raw(format!(" {} fields ", group.name)).fg(theme.label))),
        hdr,
    );
    frame.render_widget(chart, body);
}

fn render_stat_conf(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = *app.theme();
    // TODO: parse libs/firmware/**/*.conf instead of hardcoding
    render_conf_directives(frame, area, &theme, &[
        "CONFIG_STATS=y",
        "CONFIG_STATS_NAMES=y",
        "CONFIG_MCUMGR_GRP_STAT=y",
    ]);
}
