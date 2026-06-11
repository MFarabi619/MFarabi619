#![allow(dead_code)]

use alloc::{format, string::{String, ToString}, vec, vec::Vec};

pub mod mock;

use ratatui::style::Color;

use crate::theme::Theme;

#[derive(Debug, Clone)]
pub enum SourceStatus {
    Disconnected { hint: &'static str },
    Connecting   { transport: &'static str },
    Connected    { transport: String, latency_ms: u32 },
    Error        { message: String },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EventLevel { Info, Warn, Error }

impl EventLevel {
    pub fn color(self, theme: &Theme) -> Color {
        match self {
            EventLevel::Info  => theme.label,
            EventLevel::Warn  => theme.warning,
            EventLevel::Error => theme.error,
        }
    }

    pub fn icon(self) -> &'static str {
        match self {
            EventLevel::Info  => "",
            EventLevel::Warn  => "",
            EventLevel::Error => "",
        }
    }
}

#[derive(Debug, Clone)]
pub struct EventEntry {
    pub timestamp: String,
    pub level:     EventLevel,
    pub message:   String,
}

#[derive(Debug, Clone)]
pub struct ThreadEntry {
    pub name:       String,
    pub priority:   i32,
    pub state:      String,
    pub stack_used: u64,
    pub stack_size: u64,
}

impl ThreadEntry {
    pub fn stack_ratio(&self) -> f64 {
        if self.stack_size > 0 { self.stack_used as f64 / self.stack_size as f64 } else { 0.0 }
    }
}

#[derive(Debug, Clone)]
pub struct HeapPoolEntry {
    pub name:         String,
    pub block_size:   u64,
    pub total_blocks: u64,
    pub free_blocks:  u64,
    pub min_free:     u64,
}

impl HeapPoolEntry {
    pub fn used_blocks(&self) -> u64 { self.total_blocks.saturating_sub(self.free_blocks) }
    pub fn used_bytes(&self)  -> u64 { self.used_blocks() * self.block_size }
    pub fn total_bytes(&self) -> u64 { self.total_blocks * self.block_size }
    pub fn usage_ratio(&self) -> f64 {
        if self.total_blocks > 0 { self.used_blocks() as f64 / self.total_blocks as f64 } else { 0.0 }
    }
    pub fn watermark_ratio(&self) -> f64 {
        if self.total_blocks > 0 { 1.0 - (self.min_free as f64 / self.total_blocks as f64) } else { 0.0 }
    }
}

#[derive(Debug, Clone)]
pub struct StatGroupEntry {
    pub name:   String,
    pub fields: Vec<(String, u64)>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InterfaceKind { WiFi, WireGuard, Virtual, Ethernet, Dummy, Unknown }

impl InterfaceKind {
    pub fn label(self) -> &'static str {
        match self {
            InterfaceKind::WiFi      => "WiFi",
            InterfaceKind::WireGuard => "WireGuard",
            InterfaceKind::Virtual   => "Virtual",
            InterfaceKind::Ethernet  => "Ethernet",
            InterfaceKind::Dummy     => "Dummy",
            InterfaceKind::Unknown   => "Unknown",
        }
    }

    pub fn icon(self) -> &'static str {
        match self {
            InterfaceKind::WiFi      => "󰖩",
            InterfaceKind::WireGuard => "󰦝",
            InterfaceKind::Virtual   => "",
            InterfaceKind::Ethernet  => "󰈁",
            InterfaceKind::Dummy     => "",
            InterfaceKind::Unknown   => "",
        }
    }
}

#[derive(Debug, Clone)]
pub struct WifiStatus {
    pub state:        String,
    pub ssid:         String,
    pub bssid:        String,
    pub band:         String,
    pub channel:      u8,
    pub security:     String,
    pub rssi:         i32,
    pub link_mode:    String,
}

impl WifiStatus {
    pub fn rssi_ratio(&self) -> f64 {
        ((self.rssi as f64 + 90.0) / 60.0).clamp(0.0, 1.0)
    }
    pub fn rssi_color(&self, theme: &Theme) -> Color {
        let r = self.rssi_ratio();
        if r > 0.7      { theme.success }
        else if r > 0.4 { theme.warning }
        else            { theme.error   }
    }
}

#[derive(Debug, Clone, Default)]
pub struct InterfaceEntry {
    pub name:          String,
    pub kind:          InterfaceKind,
    pub link_addr:     String,
    pub mtu:           u32,
    pub flags:         String,
    pub status:        String,
    pub up:            bool,
    pub ipv4_addr:     String,
    pub ipv4_gateway:  String,
    pub dhcp_state:    Option<String>,
    pub virtual_name:  Option<String>,
    pub public_key:    Option<String>,
    pub wifi:          Option<WifiStatus>,
}

impl Default for InterfaceKind {
    fn default() -> Self { InterfaceKind::Unknown }
}

pub trait Source {
    fn label(&self) -> &str;
    fn status(&self) -> &SourceStatus;
    fn threads(&self) -> &[ThreadEntry];
    fn heap_pools(&self) -> &[HeapPoolEntry];
    fn stat_groups(&self) -> &[StatGroupEntry];
    fn interfaces(&self) -> &[InterfaceEntry];
    fn events(&self) -> &[EventEntry];
    fn poll(&mut self);
}
