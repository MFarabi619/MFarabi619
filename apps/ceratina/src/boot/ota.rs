use alloc::boxed::Box;
use defmt::info;
use esp_bootloader_esp_idf::ota::OtaImageState;
use esp_bootloader_esp_idf::ota_updater::OtaUpdater;
use esp_bootloader_esp_idf::partitions::PARTITION_TABLE_MAX_LEN;
use esp_storage::FlashStorage;

pub fn validate_ota_slot(flash: &mut FlashStorage<'_>) {
    let mut buffer = Box::new([0u8; PARTITION_TABLE_MAX_LEN]);
    let Ok(mut ota) = OtaUpdater::new(flash, &mut buffer) else {
        info!("OTA updater init failed (may not have OTA partitions)");
        return;
    };

    match ota.current_ota_state() {
        Ok(OtaImageState::New) | Ok(OtaImageState::PendingVerify) => {
            if let Err(error) = ota.set_current_ota_state(OtaImageState::Valid) {
                info!("failed to mark OTA slot valid: {:?}", error);
            } else {
                info!("marked current OTA slot as valid");
            }
        }
        Ok(state) => {
            info!("OTA slot already in state {:?}, no action needed", state);
        }
        Err(error) => {
            info!("failed to read OTA state: {:?}", error);
        }
    }
}
