use core::fmt::Write;

use defmt::info;
use embassy_time::Instant;
use heapless::String as HeaplessString;
use statig::prelude::*;

use crate::console;
use crate::state;

const MAX_STATUS_LINE_LEN: usize = 320;

#[derive(Clone, Copy)]
pub enum Event {
    ClientAccepted {
        remote_endpoint: Option<embassy_net::IpEndpoint>,
    },
    ClientDisconnected {
        disconnect_reason: DisconnectReason,
    },
}

#[derive(Clone, Copy)]
pub enum DisconnectReason {
    WelcomeMessageWriteFailed,
    StreamWriteFailed,
}

pub fn disconnect_reason_label(disconnect_reason: DisconnectReason) -> &'static str {
    match disconnect_reason {
        DisconnectReason::WelcomeMessageWriteFailed => "welcome_message_write_failed",
        DisconnectReason::StreamWriteFailed => "stream_write_failed",
    }
}

#[derive(Default)]
pub struct Lifecycle {
    last_disconnect_reason: Option<DisconnectReason>,
}

#[state_machine(initial = "State::waiting_for_client()")]
impl Lifecycle {
    #[state(entry_action = "on_waiting_for_client_entered")]
    fn waiting_for_client(event: &Event) -> Outcome<State> {
        match event {
            Event::ClientAccepted { remote_endpoint } => {
                Transition(State::streaming(remote_endpoint.clone()))
            }
            Event::ClientDisconnected { .. } => Handled,
        }
    }

    #[state(
        entry_action = "on_streaming_entered",
        exit_action = "on_streaming_exited"
    )]
    fn streaming(
        &mut self,
        remote_endpoint: &mut Option<embassy_net::IpEndpoint>,
        event: &Event,
    ) -> Outcome<State> {
        let _ = remote_endpoint;

        match event {
            Event::ClientDisconnected { disconnect_reason } => {
                self.last_disconnect_reason = Some(*disconnect_reason);
                Transition(State::waiting_for_client())
            }
            Event::ClientAccepted { remote_endpoint } => {
                Transition(State::streaming(remote_endpoint.clone()))
            }
        }
    }

    #[action]
    fn on_waiting_for_client_entered(&mut self) {
        info!(
            "TCP log mirror listening on TCP port {}",
            console::CONSOLE.tcp_log_mirror.port
        );
    }

    #[action]
    fn on_streaming_entered(
        &mut self,
        remote_endpoint: &mut Option<embassy_net::IpEndpoint>,
    ) {
        match remote_endpoint {
            Some(remote_endpoint) => {
                info!("TCP log client connected from {}", remote_endpoint);
            }
            None => {
                info!("TCP log client connected (remote endpoint unavailable)");
            }
        }
    }

    #[action]
    fn on_streaming_exited(
        &mut self,
        remote_endpoint: &mut Option<embassy_net::IpEndpoint>,
    ) {
        let disconnect_reason = self.last_disconnect_reason.take();

        match (remote_endpoint, disconnect_reason) {
            (Some(remote_endpoint), Some(disconnect_reason)) => {
                info!(
                    "TCP log client disconnected from {} (reason={})",
                    remote_endpoint,
                    disconnect_reason_label(disconnect_reason)
                );
            }
            (Some(remote_endpoint), None) => {
                info!(
                    "TCP log client disconnected from {} (reason=unknown)",
                    remote_endpoint
                );
            }
            (None, Some(disconnect_reason)) => {
                info!(
                    "TCP log client disconnected (reason={})",
                    disconnect_reason_label(disconnect_reason)
                );
            }
            (None, None) => {
                info!("TCP log client disconnected (reason=unknown)");
            }
        }
    }
}

pub fn build_status_line(sample_sequence: u32) -> HeaplessString<MAX_STATUS_LINE_LEN> {
    let uptime_milliseconds = Instant::now().as_millis();
    let wifi_initialized =
        state::WIFI_INITIALIZED.load(core::sync::atomic::Ordering::Acquire);
    let firmware_upgrade_in_progress = state::FIRMWARE_UPGRADE_IN_PROGRESS
        .load(core::sync::atomic::Ordering::Acquire);
    let co2 = state::co2_reading();

    let mut line = HeaplessString::<MAX_STATUS_LINE_LEN>::new();

    if write!(
        line,
        "seq={} uptime_ms={} wifi={} ota={} co2_ppm={:.2} temp={:.2} rh={:.2} ok={} model={} name={}\n",
        sample_sequence,
        uptime_milliseconds,
        wifi_initialized,
        firmware_upgrade_in_progress,
        co2.co2_ppm,
        co2.temperature,
        co2.humidity,
        co2.ok,
        co2.model,
        co2.name,
    )
    .is_err()
    {
        line.clear();
        let _ = write!(line, "seq={} note=truncated\n", sample_sequence);
    }

    line
}

use embassy_net::{Stack, tcp::TcpSocket};
use embassy_time::{Duration, Timer};
use statig::blocking::IntoStateMachineExt;

use crate::networking::tcp::write_all;

#[embassy_executor::task]
pub async fn task(stack: Stack<'static>) {
    let mut log_lifecycle = Lifecycle::default().state_machine();
    log_lifecycle.init();

    loop {
        static mut RECEIVE_BUFFER: [u8; console::CONSOLE.tcp_log_mirror.rx_buf_size] =
            [0; console::CONSOLE.tcp_log_mirror.rx_buf_size];
        static mut TRANSMIT_BUFFER: [u8; console::CONSOLE.tcp_log_mirror.tx_buf_size] =
            [0; console::CONSOLE.tcp_log_mirror.tx_buf_size];

        let mut tcp_socket = unsafe {
            TcpSocket::new(
                stack,
                &mut *core::ptr::addr_of_mut!(RECEIVE_BUFFER),
                &mut *core::ptr::addr_of_mut!(TRANSMIT_BUFFER),
            )
        };

        tcp_socket.set_timeout(None);

        if let Err(error) = tcp_socket
            .accept(console::CONSOLE.tcp_log_mirror.port)
            .await
        {
            info!("TCP log accept failed: {:?}", error);
            Timer::after(Duration::from_millis(250)).await;
            continue;
        }

        log_lifecycle.handle(&Event::ClientAccepted {
            remote_endpoint: tcp_socket.remote_endpoint(),
        });

        tcp_socket.set_timeout(Some(Duration::from_secs(
            console::CONSOLE.tcp_log_mirror.timeout_secs,
        )));

        if let Err(error) = write_all(
            &mut tcp_socket,
            console::CONSOLE.tcp_log_mirror.welcome_message,
        )
        .await
        {
            info!("TCP log welcome write failed: {:?}", error);
            log_lifecycle.handle(&Event::ClientDisconnected {
                disconnect_reason: DisconnectReason::WelcomeMessageWriteFailed,
            });
            continue;
        }

        let mut sample_sequence = 0u32;

        loop {
            sample_sequence = sample_sequence.wrapping_add(1);
            let status_line = build_status_line(sample_sequence);

            if let Err(error) = write_all(&mut tcp_socket, status_line.as_bytes()).await {
                info!("TCP log stream write failed: {:?}", error);
                log_lifecycle.handle(&Event::ClientDisconnected {
                    disconnect_reason: DisconnectReason::StreamWriteFailed,
                });
                break;
            }

            Timer::after(Duration::from_secs(
                console::CONSOLE.tcp_log_mirror.interval_secs,
            ))
            .await;
        }

        tcp_socket.close();
    }
}
