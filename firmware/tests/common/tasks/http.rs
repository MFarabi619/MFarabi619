//! HTTP tasks. A minimal one-shot HTTP/1.0 server backed by the SD card,
//! used by the SD-card-webpage manual integration test.

use defmt::info;
use embassy_executor::Spawner;
use embassy_net::Stack;
use embassy_net::tcp::TcpSocket;
use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::signal::Signal;
use embassy_time::Duration;
use firmware::filesystems::sd;

use crate::common::setup::Device;

pub const HTTP_LISTEN_PORT: u16 = firmware::config::app::http::PORT;

static FIRST_REQUEST_RECEIVED_SIGNAL: Signal<CriticalSectionRawMutex, ()> = Signal::new();

pub fn start_server_serving_sd(
    device: &mut Device,
    embassy_spawner: Spawner,
) -> Result<(), &'static str> {
    info!(
        "user starts the device HTTP server port={=u16}",
        HTTP_LISTEN_PORT
    );

    let embassy_network_stack = device
        .embassy_network_stack
        .ok_or("device: embassy-net stack not started — call wifi::start_access_point first")?;

    embassy_spawner.spawn(
        serve_sd_card_index_html(embassy_network_stack)
            .map_err(|_| "device: failed to allocate HTTP serving task")?,
    );
    Ok(())
}

pub async fn wait_for_first_request(_device: &mut Device) -> Result<(), &'static str> {
    info!("user is expected to open http://192.168.4.1/ in their browser");
    FIRST_REQUEST_RECEIVED_SIGNAL.wait().await;
    info!("user successfully fetched a page from the device");
    Ok(())
}

#[embassy_executor::task]
async fn serve_sd_card_index_html(embassy_network_stack: Stack<'static>) -> ! {
    let mut tcp_receive_buffer = [0u8; 1024];
    let mut tcp_transmit_buffer = [0u8; 4096];

    loop {
        let mut tcp_socket = TcpSocket::new(
            embassy_network_stack,
            &mut tcp_receive_buffer,
            &mut tcp_transmit_buffer,
        );
        tcp_socket.set_timeout(Some(Duration::from_secs(15)));

        if tcp_socket.accept(HTTP_LISTEN_PORT).await.is_err() {
            continue;
        }

        info!("device HTTP server: accepted client");
        FIRST_REQUEST_RECEIVED_SIGNAL.signal(());

        let mut request_drain_buffer = [0u8; 256];
        let _ = embedded_io_async::Read::read(&mut tcp_socket, &mut request_drain_buffer).await;

        let response_body_size_bytes = match sd::file_size("index.htm") {
            Ok(size_bytes) => size_bytes as usize,
            Err(_sd_error) => {
                let not_found_response =
                    b"HTTP/1.0 404 Not Found\r\n\r\nindex.htm not found on SD card\r\n";
                let _ = embedded_io_async::Write::write_all(&mut tcp_socket, not_found_response).await;
                let _ = tcp_socket.flush().await;
                tcp_socket.close();
                continue;
            }
        };

        let mut response_header_buffer = heapless::String::<128>::new();
        let _ = core::fmt::Write::write_fmt(
            &mut response_header_buffer,
            format_args!(
                "HTTP/1.0 200 OK\r\n\
                 Content-Type: text/html; charset=utf-8\r\n\
                 Content-Length: {}\r\n\
                 Connection: close\r\n\r\n",
                response_body_size_bytes
            ),
        );
        let _ = embedded_io_async::Write::write_all(
            &mut tcp_socket,
            response_header_buffer.as_bytes(),
        )
        .await;

        let mut current_offset_bytes: u32 = 0;
        let mut sd_read_buffer = [0u8; 512];
        while (current_offset_bytes as usize) < response_body_size_bytes {
            let bytes_read_from_sd = match sd::read_file_chunk(
                "index.htm",
                current_offset_bytes,
                &mut sd_read_buffer,
            ) {
                Ok(bytes_read) if bytes_read > 0 => bytes_read,
                _ => break,
            };
            if embedded_io_async::Write::write_all(
                &mut tcp_socket,
                &sd_read_buffer[..bytes_read_from_sd],
            )
            .await
            .is_err()
            {
                break;
            }
            current_offset_bytes += bytes_read_from_sd as u32;
        }

        let _ = tcp_socket.flush().await;
        tcp_socket.close();
    }
}
