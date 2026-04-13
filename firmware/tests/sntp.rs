//! `describe("SNTP Sync")`
//!
//! The device joins home WiFi, resolves `pool.ntp.org`, asks an NTP
//! server for the current epoch, and writes the result into the ESP32
//! LPWR RTC. `#[ignore]` because it needs an external AP + internet.

#![no_std]
#![no_main]

extern crate alloc;

#[path = "common/mod.rs"]
mod common;

use core::net::{IpAddr, SocketAddr};

use defmt::info;
use embassy_net::{dns::DnsQueryType, udp::PacketMetadata};
use esp_hal::rtc_cntl::Rtc;
use sntpc::{NtpContext, NtpTimestampGenerator, NtpUdpSocket, Result as SntpResult, get_time};

use common::{Device, tasks};

esp_bootloader_esp_idf::esp_app_desc!();

const NTP_SERVER_HOSTNAME: &str = "pool.ntp.org";
const MICROSECONDS_PER_SECOND: u64 = 1_000_000;
const MIN_PLAUSIBLE_EPOCH_SECONDS: u32 = 1_700_000_000;

#[derive(Copy, Clone)]
struct RtcBackedTimestampGenerator<'rtc> {
    rtc: &'rtc Rtc<'rtc>,
    captured_time_microseconds: u64,
}

impl NtpTimestampGenerator for RtcBackedTimestampGenerator<'_> {
    fn init(&mut self) {
        self.captured_time_microseconds = self.rtc.current_time_us();
    }

    fn timestamp_sec(&self) -> u64 {
        self.captured_time_microseconds / MICROSECONDS_PER_SECOND
    }

    fn timestamp_subsec_micros(&self) -> u32 {
        (self.captured_time_microseconds % MICROSECONDS_PER_SECOND) as u32
    }
}

struct EmbassyNetUdpSocket<'socket> {
    socket: embassy_net::udp::UdpSocket<'socket>,
}

impl NtpUdpSocket for EmbassyNetUdpSocket<'_> {
    async fn send_to(
        &self,
        buffer: &[u8],
        destination_address: core::net::SocketAddr,
    ) -> SntpResult<usize> {
        let core::net::SocketAddr::V4(destination_address_v4) = destination_address else {
            return Err(sntpc::Error::Network);
        };
        let ip_endpoint = embassy_net::IpEndpoint::from(destination_address_v4);
        self.socket
            .send_to(buffer, ip_endpoint)
            .await
            .map(|()| buffer.len())
            .map_err(|_| sntpc::Error::Network)
    }

    async fn recv_from(
        &self,
        buffer: &mut [u8],
    ) -> SntpResult<(usize, core::net::SocketAddr)> {
        let (bytes_read, udp_metadata) = self
            .socket
            .recv_from(buffer)
            .await
            .map_err(|_| sntpc::Error::Network)?;

        let embassy_net::IpEndpoint {
            addr: embassy_net::IpAddress::Ipv4(addr_v4),
            port,
        } = udp_metadata.endpoint;

        let octets = addr_v4.octets();
        let core_address = core::net::SocketAddr::V4(core::net::SocketAddrV4::new(
            core::net::Ipv4Addr::new(octets[0], octets[1], octets[2], octets[3]),
            port,
        ));
        Ok((bytes_read, core_address))
    }
}

#[cfg(test)]
#[embedded_test::setup]
fn setup() {
    rtt_target::rtt_init_defmt!();
}

#[cfg(test)]
#[embedded_test::tests(default_timeout = 60, executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;

    #[init]
    fn init() -> Device {
        info!("=== SNTP Sync — describe block ===");
        common::setup::boot_device()
    }

    /// `it("user syncs the device RTC from pool.ntp.org")`
    #[test]
    #[timeout(60)]
    async fn user_syncs_device_rtc_from_pool_ntp_org(
        mut device: Device,
    ) -> Result<(), &'static str> {
        // SAFETY: every embedded-test runs inside an `esp_rtos::embassy::Executor`.
        let embassy_spawner =
            unsafe { embassy_executor::Spawner::for_current_executor() }.await;

        tasks::wifi::connect_to_home_access_point(&mut device, embassy_spawner).await?;

        let embassy_network_stack = device
            .embassy_network_stack
            .ok_or("device: embassy-net stack missing after WiFi bring-up")?;

        info!("user resolves NTP server hostname={=str}", NTP_SERVER_HOSTNAME);
        let ntp_server_addresses = embassy_network_stack
            .dns_query(NTP_SERVER_HOSTNAME, DnsQueryType::A)
            .await
            .map_err(|_| "device: DNS lookup for pool.ntp.org failed")?;

        if ntp_server_addresses.is_empty() {
            return Err("device: DNS returned zero A records for pool.ntp.org");
        }

        let ntp_server_address: IpAddr = ntp_server_addresses[0].into();
        info!(
            "device resolved NTP server address={=[u8]:?}",
            match ntp_server_address {
                IpAddr::V4(ipv4) => ipv4.octets(),
                IpAddr::V6(_) => [0u8; 4],
            }
        );

        let mut udp_rx_metadata = [PacketMetadata::EMPTY; 16];
        let mut udp_rx_buffer = [0u8; 4096];
        let mut udp_tx_metadata = [PacketMetadata::EMPTY; 16];
        let mut udp_tx_buffer = [0u8; 4096];
        let mut udp_socket = embassy_net::udp::UdpSocket::new(
            embassy_network_stack,
            &mut udp_rx_metadata,
            &mut udp_rx_buffer,
            &mut udp_tx_metadata,
            &mut udp_tx_buffer,
        );
        udp_socket
            .bind(123)
            .map_err(|_| "device: failed to bind UDP socket to port 123")?;

        let lpwr_rtc = Rtc::new(unsafe { esp_hal::peripherals::LPWR::steal() });
        let rtc_time_before_sync_microseconds = lpwr_rtc.current_time_us();
        info!(
            "device LPWR RTC before SNTP sync us={=u64}",
            rtc_time_before_sync_microseconds
        );

        let ntp_context = NtpContext::new(RtcBackedTimestampGenerator {
            rtc: &lpwr_rtc,
            captured_time_microseconds: 0,
        });

        let udp_socket_wrapper = EmbassyNetUdpSocket { socket: udp_socket };

        let ntp_response = get_time(
            SocketAddr::from((ntp_server_address, 123)),
            &udp_socket_wrapper,
            ntp_context,
        )
        .await
        .map_err(|_| "device: SNTP get_time request failed")?;

        let synced_epoch_seconds = ntp_response.sec();
        defmt::assert!(
            synced_epoch_seconds > MIN_PLAUSIBLE_EPOCH_SECONDS,
            "NTP epoch {=u32} looks implausibly old (< 2023)",
            synced_epoch_seconds
        );

        let synced_epoch_microseconds = (synced_epoch_seconds as u64 * MICROSECONDS_PER_SECOND)
            + ((ntp_response.sec_fraction() as u64 * MICROSECONDS_PER_SECOND) >> 32);
        lpwr_rtc.set_current_time_us(synced_epoch_microseconds);

        info!(
            "device LPWR RTC synced epoch_seconds={=u32} fraction={=u32}",
            synced_epoch_seconds,
            ntp_response.sec_fraction()
        );
        Ok(())
    }
}
