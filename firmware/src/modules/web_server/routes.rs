use alloc::string::String as AllocString;

use embassy_net::Stack;
use embassy_time::Duration;
use picoserve::routing::{get, get_service, parse_path_segment};
use static_cell::StaticCell;

use super::services::{
    FileDownloadService, FileUploadService, FilesystemListService, SystemDeviceStatusService,
};

pub const HTTP_SERVER_PORT: u16 = 80;

fn filesystem_router() -> picoserve::Router<impl picoserve::routing::PathRouter> {
    picoserve::Router::new()
        .route("/list", get_service(FilesystemListService))
        .route(
            ("/file", parse_path_segment::<AllocString>()),
            get_service(FileDownloadService).post_service(FileUploadService),
        )
}

fn system_router() -> picoserve::Router<impl picoserve::routing::PathRouter> {
    picoserve::Router::new().route("/device/status", get_service(SystemDeviceStatusService))
}

fn api_router() -> picoserve::Router<impl picoserve::routing::PathRouter> {
    picoserve::Router::new()
        .nest("/filesystem", filesystem_router())
        .nest("/system", system_router())
}

macro_rules! mk_static {
    ($type:ty, $value:expr) => {{
        static STATIC_CELL: StaticCell<$type> = StaticCell::new();
        STATIC_CELL.uninit().write($value)
    }};
}

#[embassy_executor::task]
pub async fn http_server_task(stack: Stack<'static>) {
    let app = picoserve::Router::new()
        .nest("/api", api_router())
        .route(
            "/",
            get(|| async {
                (
                    ("Content-Type", "text/html; charset=utf-8"),
                    concat!(
                        "<!DOCTYPE html><html><head><title>Ceratina</title></head><body>",
                        "<h1>Ceratina Device</h1>",
                        "<p>HTTP server is running.</p>",
                        "</body></html>",
                    ),
                )
            }),
        );

    let config = mk_static!(
        picoserve::Config<Duration>,
        picoserve::Config::new(picoserve::Timeouts {
            start_read_request: Some(Duration::from_secs(5)),
            persistent_start_read_request: Some(Duration::from_secs(5)),
            read_request: Some(Duration::from_secs(2)),
            write: Some(Duration::from_secs(2)),
        })
        .keep_connection_alive()
    );

    let mut tcp_rx_buffer = [0u8; 2048];
    let mut tcp_tx_buffer = [0u8; 2048];
    let mut http_buffer = [0u8; 4096];

    loop {
        picoserve::listen_and_serve(
            0usize,
            &app,
            config,
            stack,
            HTTP_SERVER_PORT,
            &mut tcp_rx_buffer,
            &mut tcp_tx_buffer,
            &mut http_buffer,
        )
        .await;
    }
}
