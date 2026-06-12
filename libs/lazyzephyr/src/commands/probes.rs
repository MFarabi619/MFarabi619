use alloc::{boxed::Box, string::String, vec::Vec};

#[derive(Debug, Clone)]
pub struct ProbeInfo {
    pub identifier:    String,
    pub vendor_id:     u16,
    pub product_id:    u16,
    pub serial_number: Option<String>,
    pub probe_type:    String,
    pub device_path:   Option<String>,
}

pub trait ProbeRegistry {
    fn list(&mut self) -> Vec<ProbeInfo>;
}

pub struct NoopProbeRegistry;

impl ProbeRegistry for NoopProbeRegistry {
    fn list(&mut self) -> Vec<ProbeInfo> { Vec::new() }
}

pub fn noop_box() -> Box<dyn ProbeRegistry> { Box::new(NoopProbeRegistry) }
