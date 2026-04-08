use core::fmt::Write;

use alloc::string::String as AllocString;

use embassy_net::Stack;
use embassy_time::Duration;
use heapless::String as HeaplessString;
use picoserve::response::{IntoResponse, Json, StatusCode};
use picoserve::routing::{get, get_service, parse_path_segment};
use serde::Serialize;

use crate::filesystems::sd::is_supported_flat_file_name;

pub const HTTP_SERVER_PORT: u16 = 80;

// ─── CloudEvents 1.0 response types ───────────────────────────────────────────

#[derive(Serialize)]
pub struct CloudEvent<'a, D: Serialize> {
    pub specversion: &'a str,
    pub id: HeaplessString<80>,
    pub source: &'a str,
    #[serde(rename = "type")]
    pub event_type: &'a str,
    pub datacontenttype: &'a str,
    pub time: HeaplessString<{ crate::time::MAX_ISO8601_LEN }>,
    pub data: D,
}

#[derive(Serialize)]
pub struct SensorReadingData {
    pub co2_ppm: f32,
    pub temperature: f32,
    pub humidity: f32,
    pub model: &'static str,
    pub ok: bool,
}

#[derive(Serialize)]
pub struct DeviceStatusData {
    pub hostname: &'static str,
    pub platform: &'static str,
    pub uptime_seconds: u64,
    pub heap_free: usize,
    pub heap_used: usize,
    pub sd_card_mb: u32,
}

const CHUNK_SIZE: usize = 4096;

pub struct HttpAppProps {
    pub stack: Stack<'static>,
}

impl picoserve::AppBuilder for HttpAppProps {
    type PathRouter = impl picoserve::routing::PathRouter;

    fn build_app(self) -> picoserve::Router<Self::PathRouter> {
        picoserve::Router::new()
            .route("/api/cloudevents", get(cloudevents_handler))
            .route("/api/status", get(status_handler))
            .route(
                parse_path_segment::<AllocString>(),
                get_service(StaticFileService)
                    .post_service(FileUploadService),
            )
            .route("/", get_service(IndexService))
    }
}

// ─── API endpoint handlers ─────────────────────────────────────────────────────

async fn cloudevents_handler() -> impl IntoResponse {
    let co2 = crate::state::co2_reading();
    let epoch = crate::time::get_current_epoch_secs();
    let mut event_id = HeaplessString::<80>::new();
    let _ = write!(event_id, "sensor-reading-{}", epoch);

    Json(CloudEvent {
        specversion: "1.0",
        id: event_id,
        source: crate::config::CLOUD_EVENTS_SOURCE,
        event_type: crate::config::CLOUD_EVENT_TYPE,
        datacontenttype: "application/json",
        time: crate::time::format_iso8601(epoch),
        data: SensorReadingData {
            co2_ppm: co2.co2_ppm,
            temperature: co2.temperature,
            humidity: co2.humidity,
            model: co2.model,
            ok: co2.ok,
        },
    })
    .into_response()
    .with_header("Access-Control-Allow-Origin", "*")
}

async fn status_handler() -> impl IntoResponse {
    let info = crate::state::device_info();
    let epoch = crate::time::get_current_epoch_secs();
    let uptime = embassy_time::Instant::now().as_secs();
    let heap_free = esp_alloc::HEAP.free();
    let heap_used = esp_alloc::HEAP.used();

    let mut event_id = HeaplessString::<80>::new();
    let _ = write!(event_id, "device-status-{}", epoch);

    Json(CloudEvent {
        specversion: "1.0",
        id: event_id,
        source: crate::config::CLOUD_EVENTS_SOURCE,
        event_type: "com.apidae.system.device.status.v1",
        datacontenttype: "application/json",
        time: crate::time::format_iso8601(epoch),
        data: DeviceStatusData {
            hostname: crate::config::HOSTNAME,
            platform: crate::config::PLATFORM,
            uptime_seconds: uptime,
            heap_free,
            heap_used,
            sd_card_mb: info.sd_card_size_mb,
        },
    })
    .into_response()
    .with_header("Access-Control-Allow-Origin", "*")
}

// ─── Content type detection ────────────────────────────────────────────────────

fn content_type_for(name: &str) -> &'static str {
    if name.ends_with(".html") || name.ends_with(".htm") {
        "text/html; charset=utf-8"
    } else if name.ends_with(".js") {
        "application/javascript; charset=utf-8"
    } else if name.ends_with(".wasm") || name.ends_with(".was") {
        "application/wasm"
    } else if name.ends_with(".css") {
        "text/css"
    } else {
        "application/octet-stream"
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Index — serves index.htm from SD card at /
// ─────────────────────────────────────────────────────────────────────────────

struct IndexService;

impl picoserve::routing::RequestHandlerService<()> for IndexService {
    async fn call_request_handler_service<
        R: picoserve::io::Read,
        W: picoserve::response::ResponseWriter<Error = R::Error>,
    >(
        &self,
        _state: &(),
        (): (),
        request: picoserve::request::Request<'_, R>,
        response_writer: W,
    ) -> Result<picoserve::ResponseSent, W::Error> {
        let size = match crate::filesystems::sd::file_size_at("", "index.htm") {
            Ok(s) => s,
            Err(_) => {
                return (StatusCode::NOT_FOUND, "index.htm not found on SD card\n")
                    .write_to(request.body_connection.finalize().await?, response_writer)
                    .await;
            }
        };

        picoserve::response::chunked::ChunkedResponse::new(SdCardChunks {
            file_name: AllocString::from("index.htm"),
            size,
            content_type: "text/html; charset=utf-8",
        })
        .write_to(request.body_connection.finalize().await?, response_writer)
        .await
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Static file serving from SD card (chunked response)
// ─────────────────────────────────────────────────────────────────────────────

struct StaticFileService;

impl picoserve::routing::RequestHandlerService<(), (AllocString,)> for StaticFileService {
    async fn call_request_handler_service<
        R: picoserve::io::Read,
        W: picoserve::response::ResponseWriter<Error = R::Error>,
    >(
        &self,
        _state: &(),
        (file_name,): (AllocString,),
        request: picoserve::request::Request<'_, R>,
        response_writer: W,
    ) -> Result<picoserve::ResponseSent, W::Error> {
        if !is_supported_flat_file_name(&file_name) {
            return (StatusCode::BAD_REQUEST, "invalid path\n")
                .write_to(request.body_connection.finalize().await?, response_writer)
                .await;
        }

        let size = match crate::filesystems::sd::file_size_at("", &file_name) {
            Ok(s) => s,
            Err(_) => {
                return (StatusCode::NOT_FOUND, "not found\n")
                    .write_to(request.body_connection.finalize().await?, response_writer)
                    .await;
            }
        };

        let mime = content_type_for(&file_name);

        picoserve::response::chunked::ChunkedResponse::new(SdCardChunks {
            file_name,
            size,
            content_type: mime,
        })
        .write_to(request.body_connection.finalize().await?, response_writer)
        .await
    }
}

struct SdCardChunks {
    file_name: AllocString,
    size: u32,
    content_type: &'static str,
}

impl picoserve::response::chunked::Chunks for SdCardChunks {
    fn content_type(&self) -> &'static str {
        self.content_type
    }

    async fn write_chunks<W2: picoserve::io::Write>(
        self,
        mut writer: picoserve::response::chunked::ChunkWriter<W2>,
    ) -> Result<picoserve::response::chunked::ChunksWritten, W2::Error> {
        let mut offset = 0u32;
        let mut buf = [0u8; CHUNK_SIZE];

        while offset < self.size {
            let n = match crate::filesystems::sd::read_file_chunk(&self.file_name, offset, &mut buf) {
                Ok(n) if n > 0 => n,
                _ => break,
            };
            writer.write_chunk(&buf[..n]).await?;
            offset += n as u32;
        }

        writer.finalize().await
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// File upload to SD card (streaming body reader with scaled timeout)
// ─────────────────────────────────────────────────────────────────────────────

struct FileUploadService;

impl picoserve::routing::RequestHandlerService<(), (AllocString,)> for FileUploadService {
    async fn call_request_handler_service<
        R: picoserve::io::Read,
        W: picoserve::response::ResponseWriter<Error = R::Error>,
    >(
        &self,
        _state: &(),
        (file_name,): (AllocString,),
        mut request: picoserve::request::Request<'_, R>,
        response_writer: W,
    ) -> Result<picoserve::ResponseSent, W::Error> {
        if !is_supported_flat_file_name(&file_name) {
            return (StatusCode::BAD_REQUEST, "invalid path\n")
                .write_to(request.body_connection.finalize().await?, response_writer)
                .await;
        }

        use picoserve::io::Read;

        // Scale timeout with content length (10KB/s minimum, 60s floor)
        let content_length = request.body_connection.body().content_length();
        let timeout_secs = (content_length / 10_000).max(60) as u64;
        let timeout = Duration::from_secs(timeout_secs);

        let mut reader = request
            .body_connection
            .body()
            .reader()
            .with_different_timeout(timeout);

        // Read body in 4KB chunks, write each to SD card.
        // Each write_file_chunk call opens/closes the file but with 4KB chunks
        // a 376KB file only needs ~92 cycles.
        let mut chunk = [0u8; CHUNK_SIZE];
        let mut offset = 0u32;

        loop {
            // Fill the chunk buffer as much as possible before writing
            let mut filled = 0;
            while filled < CHUNK_SIZE {
                let n = reader.read(&mut chunk[filled..]).await?;
                if n == 0 {
                    break;
                }
                filled += n;
            }

            if filled == 0 {
                break;
            }

            if let Err(msg) = crate::filesystems::sd::write_file_chunk(&file_name, offset, &chunk[..filled]) {
                let mut err = HeaplessString::<128>::new();
                let _ = write!(err, "write failed at byte {}: {}\n", offset, msg);
                return (StatusCode::INTERNAL_SERVER_ERROR, err)
                    .write_to(request.body_connection.finalize().await?, response_writer)
                    .await;
            }
            offset += filled as u32;
        }

        let mut resp = HeaplessString::<64>::new();
        let _ = write!(resp, "ok {} bytes\n", offset);
        (StatusCode::OK, resp)
            .write_to(request.body_connection.finalize().await?, response_writer)
            .await
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Server config & task
// ─────────────────────────────────────────────────────────────────────────────

pub static CONFIG: picoserve::Config = picoserve::Config::new(picoserve::Timeouts {
    start_read_request: Duration::from_secs(5),
    persistent_start_read_request: Duration::from_secs(5),
    read_request: Duration::from_secs(2),
    write: Duration::from_secs(30),
})
.keep_connection_alive();

#[embassy_executor::task]
pub async fn task(
    task_id: usize,
    stack: Stack<'static>,
    app: &'static picoserve::AppRouter<HttpAppProps>,
) -> ! {
    let mut tcp_rx_buffer = [0u8; 2048];
    let mut tcp_tx_buffer = [0u8; 2048];
    let mut http_buffer = [0u8; 4096];

    picoserve::Server::new(app, &CONFIG, &mut http_buffer)
        .listen_and_serve(task_id, stack, HTTP_SERVER_PORT, &mut tcp_rx_buffer, &mut tcp_tx_buffer)
        .await
        .into_never()
}
