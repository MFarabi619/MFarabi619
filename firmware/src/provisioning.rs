use core::ffi::c_int;
use core::ffi::c_void;
use log_04::info;
use zephyr::raw::*;

use crate::wifi;

use core::cell::UnsafeCell;
use core::sync::atomic::{AtomicUsize, Ordering};

struct BodyBuffer {
    data: UnsafeCell<[u8; 256]>,
    cursor: AtomicUsize,
}

unsafe impl Sync for BodyBuffer {}

static BODY: BodyBuffer = BodyBuffer {
    data: UnsafeCell::new([0; 256]),
    cursor: AtomicUsize::new(0),
};

struct ScanResponseBuffer {
    data: UnsafeCell<[u8; 1024]>,
}

unsafe impl Sync for ScanResponseBuffer {}

static SCAN_BUF: ScanResponseBuffer = ScanResponseBuffer {
    data: UnsafeCell::new([0; 1024]),
};

struct RedirectHeader(http_header);
unsafe impl Sync for RedirectHeader {}

static REDIRECT_HEADER: RedirectHeader = RedirectHeader(http_header {
    name: b"Location\0".as_ptr() as *const _,
    value: b"/public/index.html\0".as_ptr() as *const _,
});

fn json_response(response_ctx: *mut http_response_ctx, body: &[u8], is_final: bool) {
    unsafe {
        (*response_ctx).body = body.as_ptr();
        (*response_ctx).body_len = body.len();
        (*response_ctx).final_chunk = is_final;
        (*response_ctx).status = http_status_HTTP_200_OK;
    }
}

fn error_response(response_ctx: *mut http_response_ctx, status: http_status) {
    unsafe {
        (*response_ctx).body = core::ptr::null();
        (*response_ctx).body_len = 0;
        (*response_ctx).final_chunk = true;
        (*response_ctx).status = status;
    }
}

fn accumulate_body(
    status: http_transaction_status,
    request_ctx: *const http_request_ctx,
) -> Option<&'static [u8]> {
    unsafe {
        if status == http_transaction_status_HTTP_SERVER_TRANSACTION_ABORTED
            || status == http_transaction_status_HTTP_SERVER_TRANSACTION_COMPLETE
        {
            BODY.cursor.store(0, Ordering::Relaxed);
            return None;
        }

        let data_len = (*request_ctx).data_len;
        if data_len > 0 {
            let cursor = BODY.cursor.load(Ordering::Relaxed);
            let buf = BODY.data.get();
            let available = (*buf).len() - cursor;
            let copy_len = data_len.min(available);
            if copy_len > 0 {
                core::ptr::copy_nonoverlapping(
                    (*request_ctx).data,
                    (*buf).as_mut_ptr().add(cursor),
                    copy_len,
                );
                BODY.cursor.store(cursor + copy_len, Ordering::Relaxed);
            }
        }

        if status == http_transaction_status_HTTP_SERVER_REQUEST_DATA_FINAL {
            let len = BODY.cursor.load(Ordering::Relaxed);
            BODY.cursor.store(0, Ordering::Relaxed);
            Some(core::slice::from_raw_parts((*BODY.data.get()).as_ptr(), len))
        } else {
            None
        }
    }
}

#[unsafe(no_mangle)]
extern "C" fn provisioning_index_handler(
    _client: *mut http_client_ctx,
    status: http_transaction_status,
    _request_ctx: *const http_request_ctx,
    response_ctx: *mut http_response_ctx,
    _user_data: *mut c_void,
) -> c_int {
    if status == http_transaction_status_HTTP_SERVER_TRANSACTION_ABORTED
        || status == http_transaction_status_HTTP_SERVER_TRANSACTION_COMPLETE
    {
        return 0;
    }

    if status == http_transaction_status_HTTP_SERVER_REQUEST_DATA_FINAL
        || status == http_transaction_status_HTTP_SERVER_REQUEST_DATA_MORE
    {
        unsafe {
            (*response_ctx).status = http_status_HTTP_302_FOUND;
            (*response_ctx).headers = &REDIRECT_HEADER.0;
            (*response_ctx).header_count = 1;
            (*response_ctx).body = core::ptr::null();
            (*response_ctx).body_len = 0;
            (*response_ctx).final_chunk = true;
        }
    }

    0
}

#[unsafe(no_mangle)]
extern "C" fn provisioning_status_handler(
    _client: *mut http_client_ctx,
    status: http_transaction_status,
    _request_ctx: *const http_request_ctx,
    response_ctx: *mut http_response_ctx,
    _user_data: *mut c_void,
) -> c_int {
    if status == http_transaction_status_HTTP_SERVER_TRANSACTION_ABORTED
        || status == http_transaction_status_HTTP_SERVER_TRANSACTION_COMPLETE
    {
        return 0;
    }

    if status == http_transaction_status_HTTP_SERVER_REQUEST_DATA_FINAL {
        let response: &[u8] = if wifi::is_provisioning() {
            br#"{"mode":"provisioning","ap_ssid":"ceratina-access-point"}"#
        } else {
            br#"{"mode":"connected"}"#
        };
        json_response(response_ctx, response, true);
    }

    0
}

#[unsafe(no_mangle)]
extern "C" fn provisioning_scan_handler(
    _client: *mut http_client_ctx,
    status: http_transaction_status,
    _request_ctx: *const http_request_ctx,
    response_ctx: *mut http_response_ctx,
    _user_data: *mut c_void,
) -> c_int {
    if status == http_transaction_status_HTTP_SERVER_TRANSACTION_ABORTED
        || status == http_transaction_status_HTTP_SERVER_TRANSACTION_COMPLETE
    {
        return 0;
    }

    if status == http_transaction_status_HTTP_SERVER_REQUEST_DATA_FINAL {
        if wifi::is_scan_in_progress() {
            static BUSY: &[u8] = br#"{"status":"scan_in_progress"}"#;
            json_response(response_ctx, BUSY, true);
            return 0;
        }

        wifi::start_scan();

        unsafe {
            let mut wait_count = 0;
            while wifi::is_scan_in_progress() && wait_count < 50 {
                zephyr::raw::k_msleep(100);
                wait_count += 1;
            }

            let buf = &mut *SCAN_BUF.data.get();
            let count = wifi::scan_result_count() as usize;
            let mut cursor = 0;
            buf[cursor] = b'[';
            cursor += 1;

            for index in 0..count {
                if index > 0 {
                    buf[cursor] = b',';
                    cursor += 1;
                }

                let result = &*wifi::get_scan_result(index);
                let ssid = core::str::from_utf8_unchecked(
                    &result.ssid[..result.ssid_length as usize],
                );

                let written = write_scan_entry(
                    &mut buf[cursor..],
                    ssid,
                    result.rssi,
                    result.channel,
                );
                cursor += written;
            }

            buf[cursor] = b']';
            cursor += 1;

            json_response(response_ctx, core::slice::from_raw_parts(buf.as_ptr(), cursor), true);
        }
    }

    0
}

fn write_scan_entry(buffer: &mut [u8], ssid: &str, rssi: i8, channel: u8) -> usize {
    let mut cursor = 0;

    let prefix = br#"{"ssid":""#;
    buffer[cursor..cursor + prefix.len()].copy_from_slice(prefix);
    cursor += prefix.len();

    for &byte in ssid.as_bytes() {
        if byte == b'"' || byte == b'\\' {
            buffer[cursor] = b'\\';
            cursor += 1;
        }
        buffer[cursor] = byte;
        cursor += 1;
    }

    let mid = br#"","rssi":"#;
    buffer[cursor..cursor + mid.len()].copy_from_slice(mid);
    cursor += mid.len();

    cursor += write_i8(rssi, &mut buffer[cursor..]);

    let mid2 = br#","channel":"#;
    buffer[cursor..cursor + mid2.len()].copy_from_slice(mid2);
    cursor += mid2.len();

    cursor += write_u8(channel, &mut buffer[cursor..]);

    buffer[cursor] = b'}';
    cursor += 1;

    cursor
}

fn write_i8(value: i8, buffer: &mut [u8]) -> usize {
    if value < 0 {
        buffer[0] = b'-';
        1 + write_u8(value.unsigned_abs(), &mut buffer[1..])
    } else {
        write_u8(value as u8, buffer)
    }
}

fn write_u8(value: u8, buffer: &mut [u8]) -> usize {
    if value >= 100 {
        buffer[0] = b'0' + value / 100;
        buffer[1] = b'0' + (value / 10) % 10;
        buffer[2] = b'0' + value % 10;
        3
    } else if value >= 10 {
        buffer[0] = b'0' + value / 10;
        buffer[1] = b'0' + value % 10;
        2
    } else {
        buffer[0] = b'0' + value;
        1
    }
}

#[unsafe(no_mangle)]
extern "C" fn provisioning_connect_handler(
    _client: *mut http_client_ctx,
    status: http_transaction_status,
    request_ctx: *const http_request_ctx,
    response_ctx: *mut http_response_ctx,
    _user_data: *mut c_void,
) -> c_int {
    let Some(body) = accumulate_body(status, request_ctx) else {
        return 0;
    };

    let (ssid, password) = match parse_ssid_password(body) {
        Some(pair) => pair,
        None => {
            error_response(response_ctx, http_status_HTTP_400_BAD_REQUEST);
            return 0;
        }
    };

    info!(
        "Provisioning: connecting to {}",
        core::str::from_utf8(ssid).unwrap_or("?")
    );

    let result = wifi::connect_to_network(ssid, password);
    if result == 0 {
        static OK: &[u8] = br#"{"status":"connecting"}"#;
        json_response(response_ctx, OK, true);
    } else {
        error_response(response_ctx, http_status_HTTP_500_INTERNAL_SERVER_ERROR);
    }

    0
}

#[unsafe(no_mangle)]
extern "C" fn provisioning_credentials_handler(
    _client: *mut http_client_ctx,
    status: http_transaction_status,
    _request_ctx: *const http_request_ctx,
    response_ctx: *mut http_response_ctx,
    _user_data: *mut c_void,
) -> c_int {
    if status == http_transaction_status_HTTP_SERVER_TRANSACTION_ABORTED
        || status == http_transaction_status_HTTP_SERVER_TRANSACTION_COMPLETE
    {
        return 0;
    }

    if status == http_transaction_status_HTTP_SERVER_REQUEST_DATA_FINAL {
        info!("Provisioning: deleting all credentials");
        wifi::delete_credentials();
        static OK: &[u8] = br#"{"status":"deleted"}"#;
        json_response(response_ctx, OK, true);
    }

    0
}

fn parse_ssid_password<'a>(json: &'a [u8]) -> Option<(&'a [u8], &'a [u8])> {
    let ssid = extract_json_string(json, b"\"ssid\"")?;
    let password = extract_json_string(json, b"\"password\"")?;
    Some((ssid, password))
}

fn extract_json_string<'a>(json: &'a [u8], key: &[u8]) -> Option<&'a [u8]> {
    let key_position = find_subsequence(json, key)?;
    let after_key = key_position + key.len();

    let colon_position = find_byte(&json[after_key..], b':')?;
    let after_colon = after_key + colon_position + 1;

    let quote_start = find_byte(&json[after_colon..], b'"')?;
    let value_start = after_colon + quote_start + 1;

    let mut index = value_start;
    while index < json.len() {
        if json[index] == b'\\' {
            index += 2;
            continue;
        }
        if json[index] == b'"' {
            return Some(&json[value_start..index]);
        }
        index += 1;
    }

    None
}

fn find_subsequence(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack
        .windows(needle.len())
        .position(|window| window == needle)
}

fn find_byte(data: &[u8], byte: u8) -> Option<usize> {
    data.iter().position(|&b| b == byte)
}
