pub mod http;
pub mod ota;
pub mod ssh;

#[derive(Clone, Copy)]
pub struct OtaServiceConfig {
    pub device_port: u16,
    pub rx_buf_size: usize,
    pub tx_buf_size: usize,
    pub chunk_size: usize,
}

#[derive(Clone, Copy)]
pub struct ServicesConfig {
    pub cloud_event_type: &'static str,
    pub ota: OtaServiceConfig,
}

pub const SERVICES: ServicesConfig = ServicesConfig {
    cloud_event_type: crate::config::CLOUD_EVENT_TYPE,
    ota: OtaServiceConfig {
        device_port: crate::config::ota::PORT,
        rx_buf_size: crate::config::ota::RX_BUF_SIZE,
        tx_buf_size: crate::config::ota::TX_BUF_SIZE,
        chunk_size: crate::config::ota::CHUNK_SIZE,
    },
};
