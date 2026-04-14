use embassy_time::Instant;

use crate::{
    config::board,
    filesystems::sd,
    networking, power,
    sensors::manager,
    services::{data_logger, identity},
};

pub struct StorageSnapshot {
    pub sd_card_size_mb: u32,
}

pub struct SleepStatusSnapshot {
    pub pending: bool,
    pub requested_duration_seconds: u64,
    pub wake_cause: &'static str,
}

pub struct DataLoggerSnapshot {
    pub interval_seconds: u64,
    pub path: &'static str,
}

pub struct SystemSnapshot {
    pub hostname: &'static str,
    pub platform: &'static str,
    pub ssh_user: &'static str,
    pub uptime_seconds: u64,
    pub heap_free: usize,
    pub heap_used: usize,
    pub heap_total: usize,
    pub network: networking::wifi::WifiSnapshot,
    pub storage: StorageSnapshot,
    pub sensors: manager::StatusSnapshot,
    pub sleep: SleepStatusSnapshot,
    pub data_logger: DataLoggerSnapshot,
}

pub fn snapshot() -> SystemSnapshot {
    let heap_free = esp_alloc::HEAP.free();
    let heap_used = esp_alloc::HEAP.used();
    let wifi_snapshot = networking::wifi::snapshot();
    let storage_snapshot = sd::snapshot();

    SystemSnapshot {
        hostname: identity::hostname(),
        platform: board::PLATFORM,
        ssh_user: identity::ssh_user(),
        uptime_seconds: Instant::now().as_secs(),
        heap_free,
        heap_used,
        heap_total: heap_free + heap_used,
        network: wifi_snapshot,
        storage: StorageSnapshot {
            sd_card_size_mb: storage_snapshot.sd_card_size_mb,
        },
        sensors: manager::snapshot(),
        sleep: {
            let sleep_snapshot = power::sleep::snapshot();
            SleepStatusSnapshot {
                pending: sleep_snapshot.pending,
                requested_duration_seconds: sleep_snapshot.requested_duration_seconds,
                wake_cause: sleep_snapshot.wake_cause,
            }
        },
        data_logger: {
            let data_logger_snapshot = data_logger::snapshot();
            DataLoggerSnapshot {
                interval_seconds: data_logger_snapshot.interval_seconds,
                path: data_logger_snapshot.path,
            }
        },
    }
}
