use defmt::info;
use embassy_net::{Stack, tcp::TcpSocket};
use embassy_time::{Duration, Timer};
use esp_hal::system::software_reset;
use esp_hal_ota::Ota;
use esp_storage::FlashStorage;

use crate::networking::tcp::read_exact;
use crate::state;

/// Status byte sent back to the OTA host once `ota_begin` succeeds and the
/// device is ready to receive firmware chunks. The host blocks on this byte
/// before streaming the payload, so changing it requires a matching change
/// in the host-side uploader.
const OTA_STATUS_READY: u8 = 0xA5;

/// Status byte sent back to the OTA host when `ota_begin` rejects the
/// requested firmware size or CRC. The host treats this as a fatal error
/// for the current upload attempt.
const OTA_STATUS_BEGIN_FAILED: u8 = 0xE1;

#[embassy_executor::task]
pub async fn task(stack: Stack<'static>) {
    info!("OTA receiver listening on TCP port {}", crate::config::ota::PORT);

    loop {
        static mut RX_BUFFER: [u8; crate::config::ota::RX_BUF_SIZE] = [0; crate::config::ota::RX_BUF_SIZE];
        static mut TX_BUFFER: [u8; crate::config::ota::TX_BUF_SIZE] = [0; crate::config::ota::TX_BUF_SIZE];

        let mut socket = unsafe {
            TcpSocket::new(
                stack,
                &mut *core::ptr::addr_of_mut!(RX_BUFFER),
                &mut *core::ptr::addr_of_mut!(TX_BUFFER),
            )
        };

        socket.set_timeout(Some(Duration::from_secs(10)));

        match socket.accept(crate::config::ota::PORT).await {
            Ok(()) => {
                if let Some(remote) = socket.remote_endpoint() {
                    info!("OTA host connected from {}", remote);
                } else {
                    info!("OTA host connected (remote endpoint unavailable)");
                }

                let mut header_buffer = [0u8; 8];
                if let Err(error) = read_exact(&mut socket, &mut header_buffer).await {
                    info!("failed to read OTA header: {:?}", error);
                    Timer::after(Duration::from_secs(2)).await;
                    continue;
                }

                let firmware_size = u32::from_le_bytes(
                    header_buffer[..4]
                        .try_into()
                        .expect("header_buffer[..4] is statically 4 bytes"),
                );
                let target_crc = u32::from_le_bytes(
                    header_buffer[4..8]
                        .try_into()
                        .expect("header_buffer[4..8] is statically 4 bytes"),
                );

                info!(
                    "OTA header received: size={} bytes crc={:#010x}",
                    firmware_size, target_crc
                );

                let mut ota = match Ota::new(FlashStorage::new()) {
                    Ok(ota) => ota,
                    Err(error) => {
                        info!("failed to create OTA instance: {:?}", error);
                        Timer::after(Duration::from_secs(2)).await;
                        continue;
                    }
                };

                info!(
                    "OTA booted partition: {:?}, next target partition: {:?}, image state: {:?}",
                    ota.get_currently_booted_partition(),
                    ota.get_next_ota_partition(),
                    ota.get_ota_image_state()
                );

                state::FIRMWARE_UPGRADE_IN_PROGRESS
                    .store(true, core::sync::atomic::Ordering::Release);

                if let Err(error) = ota.ota_begin(firmware_size, target_crc) {
                    info!("ota_begin failed: {:?}", error);
                    let _ = socket.write(&[OTA_STATUS_BEGIN_FAILED]).await;
                    state::FIRMWARE_UPGRADE_IN_PROGRESS
                        .store(false, core::sync::atomic::Ordering::Release);
                    Timer::after(Duration::from_secs(2)).await;
                    continue;
                }

                if socket.write(&[OTA_STATUS_READY]).await.is_err() {
                    info!("failed to send OTA ready status");
                    state::FIRMWARE_UPGRADE_IN_PROGRESS
                        .store(false, core::sync::atomic::Ordering::Release);
                    Timer::after(Duration::from_secs(2)).await;
                    continue;
                }

                let mut chunk_buffer = [0u8; crate::config::ota::CHUNK_SIZE];
                let mut bytes_received_total = 0usize;
                let mut last_reported_percent = 0u32;

                let ota_write_result: Result<(), ()> = loop {
                    let bytes_remaining =
                        (firmware_size as usize).saturating_sub(bytes_received_total);
                    if bytes_remaining == 0 {
                        break Ok(());
                    }

                    let bytes_to_read = bytes_remaining.min(crate::config::ota::CHUNK_SIZE);
                    if let Err(error) =
                        read_exact(&mut socket, &mut chunk_buffer[..bytes_to_read]).await
                    {
                        info!("failed to read OTA chunk: {:?}", error);
                        break Err(());
                    }

                    let write_complete =
                        match ota.ota_write_chunk(&chunk_buffer[..bytes_to_read]) {
                            Ok(is_done) => is_done,
                            Err(error) => {
                                info!("ota_write_chunk failed: {:?}", error);
                                break Err(());
                            }
                        };

                    bytes_received_total += bytes_to_read;

                    let progress = (ota.get_ota_progress() * 100.0) as u32;
                    if progress >= last_reported_percent + 5 || progress == 100 {
                        info!(
                            "OTA progress: {}% ({}/{} bytes)",
                            progress, bytes_received_total, firmware_size
                        );
                        last_reported_percent = progress;
                    }

                    if socket.write(&[0]).await.is_err() {
                        info!("failed to ACK OTA chunk");
                        break Err(());
                    }

                    if write_complete {
                        break Ok(());
                    }
                };

                state::FIRMWARE_UPGRADE_IN_PROGRESS
                    .store(false, core::sync::atomic::Ordering::Release);

                if ota_write_result.is_err() {
                    Timer::after(Duration::from_secs(2)).await;
                    continue;
                }

                info!("OTA payload received, flushing update");
                info!(
                    "OTA progress details: {:?}",
                    ota.get_progress_details()
                        .map(|details| (details.remaining, details.last_crc))
                );
                match ota.ota_flush(true, true) {
                    Ok(()) => {
                        info!("OTA complete, rebooting into new firmware");
                        Timer::after(Duration::from_millis(1000)).await;
                        software_reset();
                    }
                    Err(error) => {
                        info!("ota_flush failed: {:?}", error);
                        Timer::after(Duration::from_secs(2)).await;
                    }
                }
            }
            Err(error) => {
                info!("OTA accept failed: {:?}", error);
                Timer::after(Duration::from_secs(2)).await;
            }
        }
    }
}
