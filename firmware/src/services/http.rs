use core::fmt::Write;

use alloc::string::String as AllocString;

use embassy_net::Stack;
use embassy_time::Duration;
use heapless::String as HeaplessString;
use picoserve::response::{IntoResponse, Json, StatusCode};
use picoserve::routing::{get, get_service, parse_path_segment};
use serde::Serialize;

use crate::filesystems::sd::is_supported_flat_file_name;

pub use crate::config::http::PORT as HTTP_SERVER_PORT;

// ─── Combined API response ─────────────────────────────────────────────────

#[derive(Serialize)]
struct ApiResponse<'a> {
    co2: Co2Data,
    status: StatusData<'a>,
    files: heapless::Vec<FileData, 64>,
}

#[derive(Serialize)]
struct Co2Data {
    co2_ppm: f32,
    temperature: f32,
    humidity: f32,
    model: &'static str,
    ok: bool,
}

#[derive(Serialize)]
struct StatusData<'a> {
    hostname: &'a str,
    platform: &'a str,
    uptime_seconds: u64,
    heap_free: usize,
    heap_used: usize,
    sd_card_mb: u32,
}

#[derive(Serialize)]
struct FileData {
    name: HeaplessString<32>,
    size: u32,
}

const CHUNK_SIZE: usize = 4096;

pub struct HttpAppProps {
    pub stack: Stack<'static>,
}

impl picoserve::AppBuilder for HttpAppProps {
    type PathRouter = impl picoserve::routing::PathRouter;

    fn build_app(self) -> picoserve::Router<Self::PathRouter> {
        picoserve::Router::new()
            .route("/", get_service(IndexService))
            .route(
                parse_path_segment::<AllocString>(),
                get_service(StaticFileService)
                    .post_service(FileUploadService),
            )
            .route("/api", get(api_handler))
    }
}

// ─── Single API handler ─────────────────────────────────────────────────────

async fn api_handler() -> impl IntoResponse {
    let co2 = crate::state::co2_reading();
    let device_info = crate::state::device_info();
    let uptime = embassy_time::Instant::now().as_secs();
    let heap_free = esp_alloc::HEAP.free();
    let heap_used = esp_alloc::HEAP.used();

    let mut file_list = heapless::Vec::<FileData, 64>::new();
    if let Ok(entries) = crate::filesystems::sd::list_filesystem_entries() {
        for entry in &entries {
            let _ = file_list.push(FileData {
                name: entry.name.clone(),
                size: entry.size,
            });
        }
    }

    Json(ApiResponse {
        co2: Co2Data {
            co2_ppm: co2.co2_ppm,
            temperature: co2.temperature,
            humidity: co2.humidity,
            model: co2.model,
            ok: co2.ok,
        },
        status: StatusData {
            hostname: crate::config::HOSTNAME,
            platform: crate::config::PLATFORM,
            uptime_seconds: uptime,
            heap_free,
            heap_used,
            sd_card_mb: device_info.sd_card_size_mb,
        },
        files: file_list,
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
            Ok(size) => size,
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
            Ok(size) => size,
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

    async fn write_chunks<W: picoserve::io::Write>(
        self,
        mut writer: picoserve::response::chunked::ChunkWriter<W>,
    ) -> Result<picoserve::response::chunked::ChunksWritten, W::Error> {
        let mut offset = 0u32;
        let mut buffer = [0u8; CHUNK_SIZE];

        while offset < self.size {
            let bytes_read = match crate::filesystems::sd::read_file_chunk(&self.file_name, offset, &mut buffer) {
                Ok(count) if count > 0 => count,
                _ => break,
            };
            writer.write_chunk(&buffer[..bytes_read]).await?;
            offset += bytes_read as u32;
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

        let content_length = request.body_connection.body().content_length();
        let timeout_secs = (content_length / 10_000).max(60) as u64;
        let timeout = Duration::from_secs(timeout_secs);

        let mut reader = request
            .body_connection
            .body()
            .reader()
            .with_different_timeout(timeout);

        let mut chunk = [0u8; CHUNK_SIZE];
        let mut offset = 0u32;

        loop {
            let mut filled = 0;
            while filled < CHUNK_SIZE {
                let bytes_read = reader.read(&mut chunk[filled..]).await?;
                if bytes_read == 0 {
                    break;
                }
                filled += bytes_read;
            }

            if filled == 0 {
                break;
            }

            if let Err(error_message) = crate::filesystems::sd::write_file_chunk(&file_name, offset, &chunk[..filled]) {
                let mut error_response = HeaplessString::<128>::new();
                let _ = write!(error_response, "write failed at byte {}: {}\n", offset, error_message);
                return (StatusCode::INTERNAL_SERVER_ERROR, error_response)
                    .write_to(request.body_connection.finalize().await?, response_writer)
                    .await;
            }
            offset += filled as u32;
        }

        let mut success_response = HeaplessString::<64>::new();
        let _ = write!(success_response, "ok {} bytes\n", offset);
        (StatusCode::OK, success_response)
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
    let mut tcp_rx_buffer = alloc::vec![0u8; 2048];
    let mut tcp_tx_buffer = alloc::vec![0u8; 2048];
    let mut http_buffer = alloc::vec![0u8; 4096];

    picoserve::Server::new(app, &CONFIG, &mut http_buffer)
        .listen_and_serve(task_id, stack, HTTP_SERVER_PORT, &mut tcp_rx_buffer, &mut tcp_tx_buffer)
        .await
        .into_never()
}
