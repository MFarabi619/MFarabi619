//! SD card tasks. Wraps `ceratina::filesystems::sd` with screenplay-style
//! functions returning `Result<T, &'static str>`.

use defmt::info;
use ceratina::filesystems::sd::{self, SdError};

use crate::common::setup::Device;

pub const DEFAULT_INDEX_HTML_PAYLOAD: &[u8] = b"<!doctype html>\n\
<html><head><meta charset=\"utf-8\"><title>Ceratina</title></head>\n\
<body><h1>Hello from the device</h1>\n\
<p>You are reading <code>/index.htm</code> from the device's SD card.</p>\n\
</body></html>\n";

fn map_sd_card_error(_sd_error: SdError) -> &'static str {
    "device: SD card operation failed"
}

pub fn mount(_device: &mut Device) -> Result<(), &'static str> {
    info!("user mounts the device SD card");
    sd::ensure_data_csv_exists().map_err(map_sd_card_error)
}

pub fn ensure_index_html(_device: &mut Device) -> Result<(), &'static str> {
    info!("user ensures the device SD card has /index.htm");

    if let Ok(existing_file_size_bytes) = sd::file_size("index.htm")
        && existing_file_size_bytes > 0
    {
        return Ok(());
    }

    sd::overwrite_file_contents("index.htm", DEFAULT_INDEX_HTML_PAYLOAD)
        .map_err(map_sd_card_error)
}

pub fn write_then_read_back(
    _device: &mut Device,
    file_name: &str,
    payload_bytes: &[u8],
) -> Result<(), &'static str> {
    info!(
        "user writes-and-reads-back size={=usize} bytes path=/{=str}",
        payload_bytes.len(),
        file_name
    );

    sd::write_file_at("", file_name, payload_bytes).map_err(map_sd_card_error)?;

    let read_back_payload: heapless::Vec<u8, 4096> =
        sd::read_file_at::<4096>("", file_name).map_err(map_sd_card_error)?;

    if read_back_payload.len() != payload_bytes.len() {
        return Err("device: SD round-trip length mismatch");
    }
    if read_back_payload.as_slice() != payload_bytes {
        return Err("device: SD round-trip content mismatch");
    }
    Ok(())
}
