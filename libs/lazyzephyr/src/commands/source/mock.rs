use alloc::{format, string::String, vec, vec::Vec};

use super::{
    EventEntry, EventLevel, HeapPoolEntry, InterfaceEntry, InterfaceKind, Source,
    SourceStatus, StatGroupEntry, ThreadEntry, WifiStatus,
};

pub struct MockSource {
    label:       String,
    status:      SourceStatus,
    threads:     Vec<ThreadEntry>,
    heap_pools:  Vec<HeapPoolEntry>,
    stat_groups: Vec<StatGroupEntry>,
    interfaces:  Vec<InterfaceEntry>,
    events:      Vec<EventEntry>,
}

impl MockSource {
    pub fn new() -> Self {
        Self {
            label: "mock://xiao_esp32s3".into(),
            status: SourceStatus::Disconnected {
                hint: "wire a serial or http transport to connect to a xiao/walter",
            },
            threads: vec![
                ThreadEntry { name: "rust_main".into(),       priority:  0, state: "running".into(),   stack_used: 3520, stack_size: 16384 },
                ThreadEntry { name: "idle 00".into(),          priority:-16, state: "ready".into(),     stack_used:  192, stack_size:  1024 },
                ThreadEntry { name: "sysworkq".into(),         priority:  0, state: "pending".into(),   stack_used:  720, stack_size:  4096 },
                ThreadEntry { name: "net_mgmt".into(),         priority:  0, state: "pending".into(),   stack_used: 1216, stack_size:  4096 },
                ThreadEntry { name: "dhcpv4_client".into(),    priority:  0, state: "pending".into(),   stack_used:  480, stack_size:  2048 },
                ThreadEntry { name: "shell_uart".into(),       priority:  1, state: "pending".into(),   stack_used:  820, stack_size:  2048 },
                ThreadEntry { name: "mcumgr".into(),           priority:  2, state: "pending".into(),   stack_used:  960, stack_size:  2048 },
            ],
            heap_pools: vec![
                HeapPoolEntry { name: "sys_heap".into(),       block_size:   1, total_blocks: 131072, free_blocks: 84480, min_free: 78848 },
                HeapPoolEntry { name: "net_buf_pool".into(),   block_size: 256, total_blocks:     32, free_blocks:    22, min_free:    18 },
            ],
            stat_groups: vec![
                StatGroupEntry {
                    name: "net.ipv4".into(),
                    fields: vec![
                        ("pkts_recv".into(),    1240),
                        ("pkts_sent".into(),     830),
                        ("bytes_recv".into(),  98432),
                        ("bytes_sent".into(),  44210),
                    ],
                },
                StatGroupEntry {
                    name: "net.udp".into(),
                    fields: vec![("pkts_recv".into(), 220), ("pkts_sent".into(), 180)],
                },
                StatGroupEntry {
                    name: "fs.littlefs".into(),
                    fields: vec![("blocks_total".into(), 128), ("blocks_used".into(), 14)],
                },
            ],
            interfaces: vec![
                InterfaceEntry {
                    name: "wlan0".into(),
                    kind: InterfaceKind::WiFi,
                    link_addr: "8C:BF:EA:8E:AC:28".into(),
                    mtu: 1500,
                    flags: "AUTO_START,IPv4".into(),
                    status: "oper=UP, admin=UP, carrier=ON".into(),
                    up: true,
                    ipv4_addr: "10.0.0.21/24".into(),
                    ipv4_gateway: "10.0.0.1".into(),
                    dhcp_state: Some("bound".into()),
                    virtual_name: None,
                    public_key: None,
                    wifi: Some(WifiStatus {
                        state:     "COMPLETED".into(),
                        ssid:      "openws".into(),
                        bssid:     "8A:CF:84:4B:7A:51".into(),
                        band:      "2.4GHz".into(),
                        channel:   9,
                        security:  "WPA2-PSK".into(),
                        rssi:      -47,
                        link_mode: "WIFI 4 (802.11n/HT)".into(),
                    }),
                },
                InterfaceEntry {
                    name: "wlan1".into(),
                    kind: InterfaceKind::WiFi,
                    up: false,
                    status: "Interface is down".into(),
                    ..Default::default()
                },
                InterfaceEntry {
                    name: "wg0".into(),
                    kind: InterfaceKind::WireGuard,
                    mtu: 1420,
                    flags: "POINTOPOINT,NO_AUTO_START,IPv4".into(),
                    status: "oper=UP, admin=UP, carrier=ON".into(),
                    up: true,
                    ipv4_addr: "10.10.10.2/24".into(),
                    ipv4_gateway: "0.0.0.0".into(),
                    dhcp_state: Some("disabled".into()),
                    virtual_name: Some("wg0".into()),
                    public_key: Some("IWdn7sKHx6Ccj5x0PuNMGBWhIkMHQ+2rEBhFydkV9n8=".into()),
                    wifi: None,
                    ..Default::default()
                },
            ],
            events: vec![
                EventEntry { timestamp: "02:14:33".into(), level: EventLevel::Info,  message: "wifi.sta got ip 10.0.0.42".into() },
                EventEntry { timestamp: "02:13:51".into(), level: EventLevel::Info,  message: "wifi.sta connected to openws (rssi -45 dBm)".into() },
                EventEntry { timestamp: "02:12:17".into(), level: EventLevel::Info,  message: "littlefs mounted on /lfs (128 blocks, 64KB each)".into() },
                EventEntry { timestamp: "02:11:02".into(), level: EventLevel::Info,  message: "thread sysworkq spawned at prio 0 with 4KB stack".into() },
                EventEntry { timestamp: "02:10:48".into(), level: EventLevel::Info,  message: "boot complete · uptime 0s · zephyr v4.3.0".into() },
            ],
        }
    }
}

impl Default for MockSource {
    fn default() -> Self { Self::new() }
}

impl Source for MockSource {
    fn label(&self)       -> &str               { &self.label }
    fn status(&self)      -> &SourceStatus      { &self.status }
    fn threads(&self)     -> &[ThreadEntry]     { &self.threads }
    fn heap_pools(&self)  -> &[HeapPoolEntry]   { &self.heap_pools }
    fn stat_groups(&self) -> &[StatGroupEntry]  { &self.stat_groups }
    fn interfaces(&self)  -> &[InterfaceEntry]  { &self.interfaces }
    fn events(&self)      -> &[EventEntry]      { &self.events }
    fn poll(&mut self) {}
}
