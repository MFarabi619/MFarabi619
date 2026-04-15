//! OTA partition probe for the ESP32-S3 board.
//!
//! `esp-hal` exposes OTA support through `esp_bootloader_esp_idf`, but OTA
//! requires a custom partition table with `otadata`, `ota_0`, and `ota_1`
//! partitions. This test reads the current flash partition table and reports
//! whether the device is configured for OTA updates.
//!
//! If OTA partitions are found, it also reads the current boot slot and
//! image state.

#![no_std]
#![no_main]

use defmt::info;
use esp_bootloader_esp_idf::{
    ota::OtaImageState,
    ota_updater::OtaUpdater,
    partitions::{
        AppPartitionSubType, DataPartitionSubType, PartitionType,
        PARTITION_TABLE_MAX_LEN,
    },
};
use esp_storage::FlashStorage;

const OTA_APP_PARTITION_COUNT_NEEDED: usize = 2;

struct OtaProbeResult {
    partition_table_readable: bool,
    partition_count: usize,
    ota_data_partition_found: bool,
    ota_app_partition_count: usize,
    factory_partition_found: bool,
    current_partition: Option<AppPartitionSubType>,
    current_image_state: Option<OtaImageState>,
}

fn log_probe_result(probe_result: &OtaProbeResult) {
    info!("OTA probe result:");
    info!(
        "  partition table readable: {=bool}",
        probe_result.partition_table_readable
    );
    info!("  total partitions: {=usize}", probe_result.partition_count);
    info!(
        "  OTA data partition found: {=bool}",
        probe_result.ota_data_partition_found
    );
    info!(
        "  OTA app partitions: {=usize} (need {=usize})",
        probe_result.ota_app_partition_count,
        OTA_APP_PARTITION_COUNT_NEEDED
    );
    info!(
        "  factory partition found: {=bool}",
        probe_result.factory_partition_found
    );

    if let Some(partition) = probe_result.current_partition {
        info!("  current partition: {=?}", partition);
    } else {
        info!("  current partition: none (no OTA data or factory boot)");
    }

    if let Some(state) = probe_result.current_image_state {
        info!("  current image state: {:?}", state);
    } else {
        info!("  current image state: unknown");
    }

    let ota_ready = probe_result.ota_data_partition_found
        && probe_result.ota_app_partition_count >= OTA_APP_PARTITION_COUNT_NEEDED;

    if ota_ready {
        info!("OTA support is CONFIGURED on this device");
    } else {
        info!("OTA support is NOT configured on this device");
        if !probe_result.ota_data_partition_found {
            info!("  missing: otadata partition");
        }
        if probe_result.ota_app_partition_count < OTA_APP_PARTITION_COUNT_NEEDED {
            info!(
                "  missing: {} OTA app partition(s) (need at least {})",
                OTA_APP_PARTITION_COUNT_NEEDED - probe_result.ota_app_partition_count,
                OTA_APP_PARTITION_COUNT_NEEDED
            );
        }
    }
}

esp_bootloader_esp_idf::esp_app_desc!();

#[cfg(test)]
#[embedded_test::tests(executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;
    use esp_hal::interrupt::software::SoftwareInterruptControl;

    #[init]
    fn init() -> OtaProbeResult {
        let peripherals = esp_hal::init(esp_hal::Config::default());

        let timer_group_zero = esp_hal::timer::timg::TimerGroup::new(peripherals.TIMG0);
        let software_interrupts = SoftwareInterruptControl::new(peripherals.SW_INTERRUPT);
        esp_rtos::start(timer_group_zero.timer0, software_interrupts.software_interrupt0);

        rtt_target::rtt_init_defmt!();

        info!("OTA probe test initialized");

        let mut flash = FlashStorage::new(peripherals.FLASH).multicore_auto_park();
        let mut partition_buffer = [0u8; PARTITION_TABLE_MAX_LEN];

        let partition_table =
            esp_bootloader_esp_idf::partitions::read_partition_table(&mut flash, &mut partition_buffer);

        let mut probe_result = OtaProbeResult {
            partition_table_readable: false,
            partition_count: 0,
            ota_data_partition_found: false,
            ota_app_partition_count: 0,
            factory_partition_found: false,
            current_partition: None,
            current_image_state: None,
        };

        let partition_table = match partition_table {
            Ok(pt) => {
                probe_result.partition_table_readable = true;
                pt
            }
            Err(error) => {
                info!("partition table read failed: {:?}", error);
                return probe_result;
            }
        };

        for partition_entry in partition_table.iter() {
            info!(
                "partition: {} type={:?} offset={:#08x}",
                partition_entry.label(),
                partition_entry.partition_type(),
                partition_entry.offset()
            );

            match partition_entry.partition_type() {
                PartitionType::Data(DataPartitionSubType::Ota) => {
                    probe_result.ota_data_partition_found = true;
                }
                PartitionType::App(AppPartitionSubType::Ota0)
                | PartitionType::App(AppPartitionSubType::Ota1) => {
                    probe_result.ota_app_partition_count += 1;
                }
                PartitionType::App(AppPartitionSubType::Factory) => {
                    probe_result.factory_partition_found = true;
                }
                _ => {}
            }
        }

        probe_result.partition_count = partition_table.len();

        let ota_updater_result = OtaUpdater::new(&mut flash, &mut partition_buffer);

        if let Ok(mut ota_updater) = ota_updater_result {
            if let Ok(selected) = ota_updater.selected_partition() {
                probe_result.current_partition = Some(selected);
            }

            if let Ok(state) = ota_updater.current_ota_state() {
                probe_result.current_image_state = Some(state);
            }
        }

        probe_result
    }

    #[test]
    async fn probe_ota_partition_layout(probe_result: OtaProbeResult) {
        log_probe_result(&probe_result);

        defmt::assert!(
            probe_result.partition_table_readable,
            "partition table must be readable for OTA support"
        );
    }
}
