use alloc::string::String as AllocString;
use core::fmt::Write;

use crate::{config, filesystems::sd};

pub struct DataLoggerSnapshot {
    pub interval_seconds: u64,
    pub path: &'static str,
}

pub fn snapshot() -> DataLoggerSnapshot {
    DataLoggerSnapshot {
        interval_seconds: config::data_logger::SAMPLING_INTERVAL_SECS,
        path: config::sd_card::DATA_LOG_PATH,
    }
}

pub fn ensure_initialized() {
    let _ = sd::ensure_data_csv_exists();
}

pub fn append_temperature_humidity_sample(
    timestamp_millis: u64,
    temperature_celsius: f32,
    relative_humidity_percent: f32,
) -> Result<(), &'static str> {
    let mut data_csv_line = AllocString::new();
    if write!(
        data_csv_line,
        "{},{:.2},{:.2},,,,,,,,\n",
        timestamp_millis, temperature_celsius, relative_humidity_percent
    )
    .is_err()
    {
        return Err("failed to format data.csv row");
    }

    sd::append_data_csv_line(data_csv_line.as_str()).map_err(|_| "failed to append data.csv row")
}
