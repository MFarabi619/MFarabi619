pub mod carbon_dioxide;
pub mod coreutils;
pub mod microfetch;
pub mod microtop;
pub mod neopixel;
pub mod shell;
pub mod temperature_and_humidity;

#[derive(Clone, Copy)]
pub struct DataLoggerProgramConfig {
    pub sampling_interval_secs: u64,
    pub poll_retries: usize,
    pub poll_interval_ms: u64,
}

#[derive(Clone, Copy)]
pub struct ProgramsConfig {
    pub data_logger: DataLoggerProgramConfig,
}

pub const PROGRAMS: ProgramsConfig = ProgramsConfig {
    data_logger: DataLoggerProgramConfig {
        sampling_interval_secs: crate::config::data_logger::SAMPLING_INTERVAL_SECS,
        poll_retries: crate::config::data_logger::POLL_RETRIES,
        poll_interval_ms: crate::config::data_logger::POLL_INTERVAL_MS,
    },
};
