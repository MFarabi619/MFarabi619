use defmt::info;
use esp_hal_ota::Ota;
use esp_storage::FlashStorage;

pub fn validate_ota_slot() {
    let mut ota = Ota::new(FlashStorage::new()).expect("Cannot create OTA");
    if let Err(error) = ota.ota_mark_app_valid() {
        info!(
            "ota_mark_app_valid failed (may be on factory partition): {:?}",
            error
        );
    } else {
        info!("marked current OTA slot as valid");
    }
}
