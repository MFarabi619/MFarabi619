use alloc::string::String as AllocString;
use core::fmt::Write;

use embassy_time::Instant;
use heapless::{String as HeaplessString, Vec as HeaplessVec};
use picoserve::response::{IntoResponse, Json, StatusCode};

use crate::drivers::sd_card::{
    FILE_UPLOAD_MAX_BYTES, is_supported_flat_file_name, list_filesystem_entries,
    overwrite_file_contents, read_file_contents,
};
use crate::modules::api_types::{
    ApiSuccessEnvelope, FileUploadPayload, FilesystemListPayload, SystemDeviceStatusCloudEvent,
    SystemDeviceStatusData, SystemDeviceStatusDeviceData, SystemDeviceStatusNetworkData,
    SystemDeviceStatusRuntimeData, SystemDeviceStatusStorageData, build_json_error_response,
};
use crate::modules::state::app_state_snapshot;

pub struct FilesystemListService;

impl picoserve::routing::RequestHandlerService<(), ()> for FilesystemListService {
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
        match list_filesystem_entries() {
            Ok(filesystem_entries) => Json(ApiSuccessEnvelope {
                ok: true,
                data: FilesystemListPayload {
                    entries: filesystem_entries,
                },
            })
            .into_response()
            .with_status_code(StatusCode::OK)
            .write_to(request.body_connection.finalize().await?, response_writer)
            .await,
            Err(error_message) => {
                build_json_error_response("FILESYSTEM_LIST_FAILED", error_message)
                    .into_response()
                    .with_status_code(StatusCode::INTERNAL_SERVER_ERROR)
                    .write_to(request.body_connection.finalize().await?, response_writer)
                    .await
            }
        }
    }
}

pub struct SystemDeviceStatusService;

impl picoserve::routing::RequestHandlerService<(), ()> for SystemDeviceStatusService {
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
        let app_state = app_state_snapshot();
        let uptime_seconds = Instant::now()
            .as_secs()
            .saturating_sub(app_state.boot_timestamp_seconds);

        let mut cloud_event_identifier = HeaplessString::<48>::new();
        let mut runtime_uptime = HeaplessString::<24>::new();
        let _ = write!(
            cloud_event_identifier,
            "system-device-status-{}",
            app_state.boot_timestamp_seconds + uptime_seconds
        );
        let _ = write!(runtime_uptime, "{}s", uptime_seconds);

        Json(SystemDeviceStatusCloudEvent {
            specversion: "1.0",
            id: cloud_event_identifier,
            source: app_state.cloud_event_source,
            event_type: app_state.cloud_event_type,
            datacontenttype: "application/json",
            time: "2026-04-03T17:18:43Z",
            data: SystemDeviceStatusData {
                device: SystemDeviceStatusDeviceData {
                    chip_id: 0,
                    chip_model: "ESP32-S3",
                    chip_cores: 2,
                    chip_revision: 0,
                    efuse_mac: "0",
                },
                network: SystemDeviceStatusNetworkData {
                    ipv4_address: "0.0.0.0",
                    wifi_rssi: 0,
                },
                runtime: SystemDeviceStatusRuntimeData {
                    uptime: runtime_uptime,
                    uptime_seconds,
                    memory_heap_bytes: 0,
                },
                storage: SystemDeviceStatusStorageData {
                    location: "sd",
                    total_bytes: 0,
                    used_bytes: 0,
                    free_bytes: 0,
                },
            },
        })
        .into_response()
        .with_status_code(StatusCode::OK)
        .write_to(request.body_connection.finalize().await?, response_writer)
        .await
    }
}

pub struct FileDownloadService;

impl picoserve::routing::RequestHandlerService<(), (AllocString,)> for FileDownloadService {
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
            return build_json_error_response("INVALID_PATH", "invalid file path")
                .into_response()
                .with_status_code(StatusCode::BAD_REQUEST)
                .write_to(request.body_connection.finalize().await?, response_writer)
                .await;
        }

        match read_file_contents::<8192>(&file_name) {
            Ok(file_contents) => match core::str::from_utf8(file_contents.as_slice()) {
                Ok(file_text) => (
                    StatusCode::OK,
                    ("Content-Type", "text/csv; charset=utf-8"),
                    format_args!("{}", file_text),
                )
                    .write_to(request.body_connection.finalize().await?, response_writer)
                    .await,
                Err(_) => build_json_error_response(
                    "FILE_UTF8_DECODE_FAILED",
                    "file is not valid UTF-8 text",
                )
                .into_response()
                .with_status_code(StatusCode::INTERNAL_SERVER_ERROR)
                .write_to(request.body_connection.finalize().await?, response_writer)
                .await,
            },
            Err(error_message) => {
                if error_message == "failed to open requested file" {
                    build_json_error_response("NOT_FOUND", "file not found")
                        .into_response()
                        .with_status_code(StatusCode::NOT_FOUND)
                        .write_to(request.body_connection.finalize().await?, response_writer)
                        .await
                } else {
                    build_json_error_response("FILE_READ_FAILED", error_message)
                        .into_response()
                        .with_status_code(StatusCode::INTERNAL_SERVER_ERROR)
                        .write_to(request.body_connection.finalize().await?, response_writer)
                        .await
                }
            }
        }
    }
}

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
            return build_json_error_response("INVALID_PATH", "invalid file path")
                .into_response()
                .with_status_code(StatusCode::BAD_REQUEST)
                .write_to(request.body_connection.finalize().await?, response_writer)
                .await;
        }

        if request.body_connection.content_length() > FILE_UPLOAD_MAX_BYTES {
            return build_json_error_response(
                "UPLOAD_TOO_LARGE",
                "uploaded file exceeds maximum allowed size",
            )
            .into_response()
            .with_status_code(StatusCode::PAYLOAD_TOO_LARGE)
            .write_to(request.body_connection.finalize().await?, response_writer)
            .await;
        }

        use picoserve::io::Read;

        let mut request_body_reader = request.body_connection.body().reader();
        let mut read_chunk_buffer = [0u8; 256];
        let mut uploaded_file_contents = HeaplessVec::<u8, FILE_UPLOAD_MAX_BYTES>::new();

        loop {
            let read_byte_count = request_body_reader.read(&mut read_chunk_buffer).await?;
            if read_byte_count == 0 {
                break;
            }

            for &read_byte in &read_chunk_buffer[..read_byte_count] {
                if uploaded_file_contents.push(read_byte).is_err() {
                    return build_json_error_response(
                        "UPLOAD_TOO_LARGE",
                        "uploaded file exceeds maximum allowed size",
                    )
                    .into_response()
                    .with_status_code(StatusCode::PAYLOAD_TOO_LARGE)
                    .write_to(request.body_connection.finalize().await?, response_writer)
                    .await;
                }
            }
        }

        match overwrite_file_contents(&file_name, uploaded_file_contents.as_slice()) {
            Ok(()) => {
                let mut normalized_file_name = HeaplessString::<32>::new();
                let _ = write!(normalized_file_name, "{}", file_name);
                Json(ApiSuccessEnvelope {
                    ok: true,
                    data: FileUploadPayload {
                        name: normalized_file_name,
                        size: uploaded_file_contents.len(),
                    },
                })
                .into_response()
                .with_status_code(StatusCode::OK)
                .write_to(request.body_connection.finalize().await?, response_writer)
                .await
            }
            Err(error_message) => {
                build_json_error_response("UPLOAD_WRITE_FAILED", error_message)
                    .into_response()
                    .with_status_code(StatusCode::INTERNAL_SERVER_ERROR)
                    .write_to(request.body_connection.finalize().await?, response_writer)
                    .await
            }
        }
    }
}
