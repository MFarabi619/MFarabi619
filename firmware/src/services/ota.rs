use alloc::boxed::Box;
use core::sync::atomic::{AtomicBool, Ordering};
use defmt::info;
use embassy_net::{Stack, tcp::TcpSocket};
use embassy_time::{Duration, Timer};
use embedded_storage::Storage;
use esp_bootloader_esp_idf::ota::OtaImageState;
use esp_bootloader_esp_idf::ota_updater::OtaUpdater;
use esp_bootloader_esp_idf::partitions::PARTITION_TABLE_MAX_LEN;
use esp_hal::system::software_reset;
use esp_storage::FlashStorage;

use crate::networking::tcp::read_exact;

static FIRMWARE_UPGRADE_IN_PROGRESS: AtomicBool = AtomicBool::new(false);

const OTA_STATUS_READY: u8 = 0xA5;
const OTA_STATUS_BEGIN_FAILED: u8 = 0xE1;

#[embassy_executor::task]
pub async fn task(stack: Stack<'static>, mut flash: FlashStorage<'static>) {
    info!("OTA receiver listening on TCP port {}", crate::config::app::ota::PORT);

    loop {
        static mut RX_BUFFER: [u8; crate::config::app::ota::RX_BUF_SIZE] = [0; crate::config::app::ota::RX_BUF_SIZE];
        static mut TX_BUFFER: [u8; crate::config::app::ota::TX_BUF_SIZE] = [0; crate::config::app::ota::TX_BUF_SIZE];

        let mut socket = unsafe {
            TcpSocket::new(
                stack,
                &mut *core::ptr::addr_of_mut!(RX_BUFFER),
                &mut *core::ptr::addr_of_mut!(TX_BUFFER),
            )
        };

        socket.set_timeout(Some(Duration::from_secs(10)));

        match socket.accept(crate::config::app::ota::PORT).await {
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
                let _target_crc = u32::from_le_bytes(
                    header_buffer[4..8]
                        .try_into()
                        .expect("header_buffer[4..8] is statically 4 bytes"),
                );

                info!("OTA header received: size={} bytes", firmware_size);

                let mut pt_buffer = Box::new([0u8; PARTITION_TABLE_MAX_LEN]);
                let mut ota = match OtaUpdater::new(&mut flash, &mut pt_buffer) {
                    Ok(ota) => ota,
                    Err(error) => {
                        info!("failed to create OTA updater: {:?}", error);
                        let _ = socket.write(&[OTA_STATUS_BEGIN_FAILED]).await;
                        Timer::after(Duration::from_secs(2)).await;
                        continue;
                    }
                };

                let (mut target_partition, target_slot) = match ota.next_partition() {
                    Ok(result) => result,
                    Err(error) => {
                        info!("failed to get next OTA partition: {:?}", error);
                        let _ = socket.write(&[OTA_STATUS_BEGIN_FAILED]).await;
                        Timer::after(Duration::from_secs(2)).await;
                        continue;
                    }
                };

                info!("OTA target partition: {:?}", target_slot);

                FIRMWARE_UPGRADE_IN_PROGRESS.store(true, Ordering::Release);

                if socket.write(&[OTA_STATUS_READY]).await.is_err() {
                    info!("failed to send OTA ready status");
                    FIRMWARE_UPGRADE_IN_PROGRESS.store(false, Ordering::Release);
                    Timer::after(Duration::from_secs(2)).await;
                    continue;
                }

                let mut chunk_buffer = [0u8; crate::config::app::ota::CHUNK_SIZE];
                let mut bytes_written: u32 = 0;
                let mut last_reported_percent: u32 = 0;

                let write_result: Result<(), ()> = loop {
                    let bytes_remaining = (firmware_size).saturating_sub(bytes_written);
                    if bytes_remaining == 0 {
                        break Ok(());
                    }

                    let bytes_to_read = (bytes_remaining as usize).min(crate::config::app::ota::CHUNK_SIZE);
                    if let Err(error) =
                        read_exact(&mut socket, &mut chunk_buffer[..bytes_to_read]).await
                    {
                        info!("failed to read OTA chunk: {:?}", error);
                        break Err(());
                    }

                    if let Err(error) = target_partition.write(bytes_written, &chunk_buffer[..bytes_to_read]) {
                        info!("failed to write OTA chunk at offset {}: {:?}", bytes_written, error);
                        break Err(());
                    }

                    bytes_written += bytes_to_read as u32;

                    let progress = if firmware_size > 0 {
                        (bytes_written as u64 * 100 / firmware_size as u64) as u32
                    } else {
                        0
                    };
                    if progress >= last_reported_percent + 5 || progress == 100 {
                        info!(
                            "OTA progress: {}% ({}/{} bytes)",
                            progress, bytes_written, firmware_size
                        );
                        last_reported_percent = progress;
                    }

                    if socket.write(&[0]).await.is_err() {
                        info!("failed to ACK OTA chunk");
                        break Err(());
                    }
                };

                FIRMWARE_UPGRADE_IN_PROGRESS.store(false, Ordering::Release);

                if write_result.is_err() {
                    Timer::after(Duration::from_secs(2)).await;
                    continue;
                }

                info!("OTA payload received ({} bytes), activating partition", bytes_written);

                if let Err(error) = ota.activate_next_partition() {
                    info!("failed to activate next partition: {:?}", error);
                    Timer::after(Duration::from_secs(2)).await;
                    continue;
                }

                if let Err(error) = ota.set_current_ota_state(OtaImageState::New) {
                    info!("failed to set OTA state to New: {:?}", error);
                }

                info!("OTA complete, rebooting into new firmware");
                Timer::after(Duration::from_millis(1000)).await;
                software_reset();
            }
            Err(error) => {
                info!("OTA accept failed: {:?}", error);
                Timer::after(Duration::from_secs(2)).await;
            }
        }
    }
}

pub fn spawn(spawner: &embassy_executor::Spawner, stack: Stack<'static>, flash: FlashStorage<'static>) {
    spawner.spawn(task(stack, flash).unwrap());
}
