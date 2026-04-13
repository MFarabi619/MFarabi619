use defmt::info;
use embassy_net::Stack;
use embassy_time::{Duration, Timer};

use crate::config;

#[derive(Clone, Copy)]
pub struct TimestampGenerator;

impl sntpc::NtpTimestampGenerator for TimestampGenerator {
    fn init(&mut self) {}
    fn timestamp_sec(&self) -> u64 {
        embassy_time::Instant::now().as_secs()
    }
    fn timestamp_subsec_micros(&self) -> u32 {
        (embassy_time::Instant::now().as_micros() % 1_000_000) as u32
    }
}

pub struct UdpSocket<'a> {
    pub socket: embassy_net::udp::UdpSocket<'a>,
}

impl sntpc::NtpUdpSocket for UdpSocket<'_> {
    async fn send_to(
        &self,
        buf: &[u8],
        addr: core::net::SocketAddr,
    ) -> sntpc::Result<usize> {
        let core::net::SocketAddr::V4(addr_v4) = addr else {
            return Err(sntpc::Error::Network);
        };

        self.socket
            .send_to(buf, embassy_net::IpEndpoint::from(addr_v4))
            .await
            .map(|()| buf.len())
            .map_err(|_| sntpc::Error::Network)
    }

    async fn recv_from(
        &self,
        buf: &mut [u8],
    ) -> sntpc::Result<(usize, core::net::SocketAddr)> {
        let (bytes_read, udp_meta) = self
            .socket
            .recv_from(buf)
            .await
            .map_err(|_| sntpc::Error::Network)?;

        let embassy_net::IpEndpoint {
            addr: embassy_net::IpAddress::Ipv4(addr_v4),
            port,
        } = udp_meta.endpoint;

        let octets = addr_v4.octets();
        Ok((
            bytes_read,
            core::net::SocketAddr::V4(core::net::SocketAddrV4::new(
                core::net::Ipv4Addr::new(octets[0], octets[1], octets[2], octets[3]),
                port,
            )),
        ))
    }
}

pub async fn sntp_sync_loop(stack: Stack<'static>, ntp_server: &str) -> ! {
    use embassy_net::dns::DnsQueryType;

    loop {
        let ntp_addrs = match stack.dns_query(ntp_server, DnsQueryType::A).await {
            Ok(addrs) if !addrs.is_empty() => addrs,
            Ok(_) => {
                info!("SNTP: DNS resolution for {} returned empty", ntp_server);
                Timer::after(Duration::from_secs(config::sntp::RETRY_INTERVAL_SECS)).await;
                continue;
            }
            Err(error) => {
                info!("SNTP: DNS resolution failed: {:?}", error);
                Timer::after(Duration::from_secs(config::sntp::RETRY_INTERVAL_SECS)).await;
                continue;
            }
        };

        let ntp_addr: core::net::IpAddr = ntp_addrs[0].into();
        info!("SNTP: Resolved {} to {}", ntp_server, ntp_addr);

        let mut sync_succeeded = false;

        for attempt in 0..config::sntp::MAX_ATTEMPTS {
            info!("SNTP: sync attempt {}/{}", attempt + 1, config::sntp::MAX_ATTEMPTS);

            let mut rx_meta = [embassy_net::udp::PacketMetadata::EMPTY; 16];
            let mut rx_buffer = alloc::vec![0u8; 4096];
            let mut tx_meta = [embassy_net::udp::PacketMetadata::EMPTY; 16];
            let mut tx_buffer = alloc::vec![0u8; 4096];

            let mut udp_socket = embassy_net::udp::UdpSocket::new(
                stack,
                &mut rx_meta,
                &mut rx_buffer,
                &mut tx_meta,
                &mut tx_buffer,
            );

            if let Err(error) = udp_socket.bind(123) {
                info!("SNTP: failed to bind UDP socket: {:?}", error);
                Timer::after(Duration::from_secs(config::sntp::ATTEMPT_INTERVAL_SECS)).await;
                continue;
            }

            let ntp_context = sntpc::NtpContext::new(TimestampGenerator);

            match sntpc::get_time(
                core::net::SocketAddr::from((ntp_addr, 123)),
                &UdpSocket { socket: udp_socket },
                ntp_context,
            )
            .await
            {
                Ok(ntp_time) => {
                    let epoch_secs = ntp_time.sec() as u64;

                    crate::time::set_time_synced(epoch_secs);

                    info!(
                        "SNTP: sync successful, epoch={} ({})",
                        epoch_secs,
                        crate::time::format_iso8601(epoch_secs).as_str()
                    );

                    sync_succeeded = true;
                    break;
                }
                Err(_error) => {
                    info!("SNTP: sync attempt {} failed", attempt + 1);
                    Timer::after(Duration::from_secs(config::sntp::ATTEMPT_INTERVAL_SECS)).await;
                }
            }
        }

        if !sync_succeeded {
            info!(
                "SNTP: all {} attempts failed, retrying in {}s",
                config::sntp::MAX_ATTEMPTS, config::sntp::RETRY_INTERVAL_SECS
            );
        }

        Timer::after(Duration::from_secs(config::sntp::RETRY_INTERVAL_SECS)).await;
    }
}

#[embassy_executor::task]
pub async fn task(stack: Stack<'static>) {
    sntp_sync_loop(stack, crate::config::NTP_SERVER).await
}
