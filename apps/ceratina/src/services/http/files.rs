use alloc::string::String as AllocString;

use picoserve::response::{IntoResponse, StatusCode};

use crate::filesystems::sd::is_supported_flat_file_name;

const CHUNK_SIZE: usize = 4096;

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

pub struct IndexService;

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

pub struct StaticFileService;

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

        let content_type = content_type_for(&file_name);

        picoserve::response::chunked::ChunkedResponse::new(SdCardChunks {
            file_name,
            size,
            content_type,
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
            let bytes_read = match crate::filesystems::sd::read_file_chunk(
                &self.file_name,
                offset,
                &mut buffer,
            ) {
                Ok(count) if count > 0 => count,
                _ => break,
            };
            writer.write_chunk(&buffer[..bytes_read]).await?;
            offset += bytes_read as u32;
        }

        writer.finalize().await
    }
}
