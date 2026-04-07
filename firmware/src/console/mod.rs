pub mod icons;
pub mod log;

#[derive(Clone, Copy)]
pub struct TcpLogMirrorConfig {
    pub port: u16,
    pub rx_buf_size: usize,
    pub tx_buf_size: usize,
    pub interval_secs: u64,
    pub timeout_secs: u64,
    pub welcome_message: &'static [u8],
}

#[derive(Clone, Copy)]
pub struct ConsoleConfig {
    pub tcp_log_mirror: TcpLogMirrorConfig,
}

pub const CONSOLE: ConsoleConfig = ConsoleConfig {
    tcp_log_mirror: TcpLogMirrorConfig {
        port: crate::config::tcp_log::PORT,
        rx_buf_size: crate::config::tcp_log::RX_BUF_SIZE,
        tx_buf_size: crate::config::tcp_log::TX_BUF_SIZE,
        interval_secs: crate::config::tcp_log::INTERVAL_SECS,
        timeout_secs: crate::config::tcp_log::TIMEOUT_SECS,
        welcome_message: crate::config::tcp_log::WELCOME,
    },
};
