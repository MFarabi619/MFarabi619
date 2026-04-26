use core::fmt::Write;

use alloc::string::String as AllocString;
use embassy_time::Duration;
use heapless::String as HeaplessString;
use picoserve::response::{IntoResponse, StatusCode};

use crate::filesystems::sd::is_supported_flat_file_name;

const CHUNK_SIZE: usize = 4096;

pub struct FileUploadService;

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

            if let Err(error_message) =
                crate::filesystems::sd::write_file_chunk(&file_name, offset, &chunk[..filled])
            {
                let mut error_response = HeaplessString::<128>::new();
                let _ = write!(
                    error_response,
                    "write failed at byte {}: {}\n",
                    offset,
                    error_message
                );
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
