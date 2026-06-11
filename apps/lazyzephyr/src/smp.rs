use std::time::{Duration, Instant};

use anyhow::Result;
use mcumgr_toolkit::MCUmgrClient;
use lazyzephyr_core::source::{
    EventEntry, HeapPoolEntry, InterfaceEntry, InterfaceKind, Source, SourceStatus,
    StatGroupEntry, ThreadEntry, WifiStatus,
};

const POLL_INTERVAL: Duration = Duration::from_secs(2);
const SMP_TIMEOUT:   Duration = Duration::from_millis(1500);
const BAUDRATE:      u32      = 115_200;
const AUTO_MATCH:    &str     = ".*";

pub struct SmpSerialSource {
    client:      MCUmgrClient,
    label:       String,
    status:      SourceStatus,
    last_poll:   Instant,
    app_info:    Option<String>,
    stat_names:  Vec<String>,
    threads:     Vec<ThreadEntry>,
    heap_pools:  Vec<HeapPoolEntry>,
    stat_groups: Vec<StatGroupEntry>,
    interfaces:  Vec<InterfaceEntry>,
}

impl SmpSerialSource {
    pub fn auto() -> Result<Self> {
        let client = MCUmgrClient::new_from_usb_serial(AUTO_MATCH, BAUDRATE, SMP_TIMEOUT)?;
        let _ = client.use_auto_frame_size();
        Ok(Self {
            client,
            label:       "smp · auto".into(),
            status:      SourceStatus::Connecting { transport: "uart" },
            last_poll:   Instant::now() - POLL_INTERVAL * 2,
            app_info:    None,
            stat_names:  Vec::new(),
            threads:     Vec::new(),
            heap_pools:  Vec::new(),
            stat_groups: Vec::new(),
            interfaces:  Vec::new(),
        })
    }

    fn refresh(&mut self) {
        let started = Instant::now();
        match self.try_refresh() {
            Ok(()) => {
                self.status = SourceStatus::Connected {
                    transport:  format!("uart · {} threads · {} stat", self.threads.len(), self.stat_groups.len()),
                    latency_ms: started.elapsed().as_millis() as u32,
                };
            }
            Err(error) => {
                self.status = SourceStatus::Error { message: error.to_string() };
            }
        }
    }

    fn try_refresh(&mut self) -> Result<()> {
        self.client.check_connection()?;
        if self.app_info.is_none() {
            self.app_info = self.client.os_application_info(None).ok();
        }
        if self.stat_names.is_empty() {
            self.stat_names = self.client.stats_list_groups().unwrap_or_default();
        }

        self.threads = self.client.os_task_statistics().unwrap_or_default().into_iter()
            .map(|(name, stats)| ThreadEntry {
                name,
                priority:   stats.prio,
                state:      decode_thread_state(stats.state),
                stack_used: stats.stkuse.unwrap_or(0),
                stack_size: stats.stksiz.unwrap_or(0),
            })
            .collect();
        self.threads.sort_by(|a, b| a.name.cmp(&b.name));

        self.heap_pools = self.client.os_memory_pool_statistics().unwrap_or_default().into_iter()
            .map(|(name, pool)| HeapPoolEntry {
                name,
                block_size:   pool.blksiz,
                total_blocks: pool.nblks,
                free_blocks:  pool.nfree,
                min_free:     pool.min,
            })
            .collect();
        self.heap_pools.sort_by(|a, b| a.name.cmp(&b.name));

        let mut groups: Vec<StatGroupEntry> = Vec::with_capacity(self.stat_names.len());
        for name in &self.stat_names {
            if let Ok(data) = self.client.stats_get_group_data(name) {
                let mut fields: Vec<(String, u64)> = data.into_iter().collect();
                fields.sort_by(|a, b| a.0.cmp(&b.0));
                groups.push(StatGroupEntry { name: name.clone(), fields });
            }
        }
        groups.sort_by(|a, b| a.name.cmp(&b.name));
        self.stat_groups = groups;

        self.interfaces = self.fetch_interfaces();

        Ok(())
    }

    fn fetch_interfaces(&mut self) -> Vec<InterfaceEntry> {
        let Ok((_, iface_text)) = self.client.shell_execute(&["net".into(), "iface".into()], false) else {
            return Vec::new();
        };
        let mut entries = parse_net_iface(&iface_text);
        if entries.iter().any(|entry| entry.kind == InterfaceKind::WiFi) {
            if let Ok((_, wifi_text)) = self.client.shell_execute(&["wifi".into(), "status".into()], false) {
                if let Some(wifi) = parse_wifi_status(&wifi_text) {
                    if let Some(target) = entries.iter_mut().find(|entry| entry.kind == InterfaceKind::WiFi) {
                        target.wifi = Some(wifi);
                    }
                }
            }
        }
        entries
    }
}

impl Source for SmpSerialSource {
    fn label(&self)       -> &str             { &self.label }
    fn status(&self)      -> &SourceStatus    { &self.status }
    fn threads(&self)     -> &[ThreadEntry]   { &self.threads }
    fn heap_pools(&self)  -> &[HeapPoolEntry] { &self.heap_pools }
    fn stat_groups(&self) -> &[StatGroupEntry]{ &self.stat_groups }
    fn interfaces(&self)  -> &[InterfaceEntry]{ &self.interfaces }
    fn events(&self)      -> &[EventEntry]    { &[] }

    fn poll(&mut self) {
        if self.last_poll.elapsed() >= POLL_INTERVAL {
            self.refresh();
            self.last_poll = Instant::now();
        }
    }
}

fn parse_net_iface(text: &str) -> Vec<InterfaceEntry> {
    let mut entries: Vec<InterfaceEntry> = Vec::new();
    let mut current: Option<InterfaceEntry> = None;

    for raw_line in text.lines() {
        let line = raw_line.trim();
        if line.starts_with("Interface ") {
            if let Some(done) = current.take() { entries.push(done); }
            current = Some(parse_iface_header(line));
            continue;
        }
        let Some(entry) = current.as_mut() else { continue };
        if let Some(value) = line.strip_prefix("Link addr") {
            entry.link_addr = value.trim_start_matches([':', ' ']).into();
        } else if let Some(value) = line.strip_prefix("MTU") {
            entry.mtu = value.trim_start_matches([':', ' ']).parse().unwrap_or(0);
        } else if let Some(value) = line.strip_prefix("Flags") {
            let raw = value.trim_start_matches([':', ' ']).to_string();
            entry.up = raw.contains("UP");
            entry.flags = raw;
        } else if let Some(value) = line.strip_prefix("Status") {
            entry.status = value.trim_start_matches([':', ' ']).into();
        } else if let Some(value) = line.strip_prefix("IPv4 gateway") {
            entry.ipv4_gateway = value.trim_start_matches([':', ' ']).into();
        } else if let Some(value) = line.strip_prefix("Virtual name") {
            entry.virtual_name = Some(value.trim_start_matches([':', ' ']).into());
        } else if let Some(value) = line.strip_prefix("Public key") {
            entry.public_key = Some(value.trim_start_matches([':', ' ']).into());
        } else if let Some(value) = line.strip_prefix("DHCPv4 state") {
            entry.dhcp_state = Some(value.trim_start_matches([':', ' ']).into());
        } else if entry.ipv4_addr.is_empty() && line.contains('/') && line.chars().next().map_or(false, |c| c.is_ascii_digit()) {
            if let Some(token) = line.split_whitespace().next() {
                entry.ipv4_addr = token.into();
            }
        }
    }
    if let Some(done) = current.take() { entries.push(done); }
    entries
}

fn parse_iface_header(line: &str) -> InterfaceEntry {
    let mut entry = InterfaceEntry::default();
    let after = line.strip_prefix("Interface ").unwrap_or(line);
    let name_part = after.split_whitespace().next().unwrap_or("");
    entry.name = name_part.into();
    let kind_token = line
        .rsplit_once('(')
        .map(|(_, tail)| tail.trim_end_matches(')').trim().to_string())
        .unwrap_or_default();
    entry.kind = match kind_token.to_ascii_lowercase().as_str() {
        token if token.contains("ieee 802.11") || token.contains("wifi") || token.contains("wlan") => InterfaceKind::WiFi,
        token if token.contains("virtual")  => InterfaceKind::Virtual,
        token if token.contains("ethernet") => InterfaceKind::Ethernet,
        token if token.contains("dummy")    => InterfaceKind::Dummy,
        _ => InterfaceKind::Unknown,
    };
    entry
}

fn parse_wifi_status(text: &str) -> Option<WifiStatus> {
    let mut status = WifiStatus {
        state:     String::new(),
        ssid:      String::new(),
        bssid:     String::new(),
        band:      String::new(),
        channel:   0,
        security:  String::new(),
        rssi:      -100,
        link_mode: String::new(),
    };
    let mut any = false;
    for raw_line in text.lines() {
        let line = raw_line.trim();
        let Some((key, value)) = line.split_once(':') else { continue };
        let key = key.trim().to_ascii_lowercase();
        let value = value.trim();
        any = true;
        match key.as_str() {
            "state"            => status.state     = value.into(),
            "ssid"             => status.ssid      = value.into(),
            "bssid"            => status.bssid     = value.into(),
            "band"             => status.band      = value.into(),
            "channel"          => status.channel   = value.parse().unwrap_or(0),
            "security"         => status.security  = value.into(),
            "rssi"             => status.rssi      = value.split_whitespace().next().and_then(|s| s.parse().ok()).unwrap_or(-100),
            "link mode"        => status.link_mode = value.into(),
            "beacon interval"  => {}
            _ => {}
        }
    }
    if any { Some(status) } else { None }
}

fn decode_thread_state(raw: u32) -> String {
    const PENDING:   u32 = 1 << 1;
    const PRESTART:  u32 = 1 << 2;
    const DEAD:      u32 = 1 << 3;
    const SUSPENDED: u32 = 1 << 4;
    const QUEUED:    u32 = 1 << 7;
    if raw & DEAD      != 0 { return "dead".into(); }
    if raw & PRESTART  != 0 { return "prestart".into(); }
    if raw & SUSPENDED != 0 { return "suspended".into(); }
    if raw & PENDING   != 0 { return "pending".into(); }
    if raw & QUEUED    != 0 { return "ready".into(); }
    "running".into()
}
