use core::ffi::c_int;
use core::ffi::c_void;
use log_04::info;
use zephyr::raw::*;

use crate::wifi;

static SETUP_HTML: &[u8] = br#"<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Ceratina Setup</title><style>*{box-sizing:border-box;font-family:system-ui}body{max-width:400px;margin:40px auto;padding:0 16px}h1{font-size:1.4em}button,input,select{width:100%;padding:10px;margin:4px 0;border:1px solid #ccc;border-radius:4px;font-size:1em}button{background:#333;color:#fff;border:0;cursor:pointer}button:active{background:#555}#networks{margin:12px 0}#msg{padding:8px;margin:8px 0;border-radius:4px;display:none}.ok{background:#d4edda;display:block!important}.err{background:#f8d7da;display:block!important}</style></head><body><h1>Ceratina WiFi Setup</h1><button onclick="scan()">Scan Networks</button><div id="networks"></div><form onsubmit="return connect(event)"><input id="ssid" placeholder="SSID" required><input id="psk" type="password" placeholder="Password" required><button type="submit">Connect</button></form><div id="msg"></div><script>function scan(){fetch('/api/wifi/scan',{method:'POST'}).then(r=>r.json()).then(d=>{let h='';d.forEach(n=>{h+='<button type="button" onclick="document.getElementById(\'ssid\').value=\''+n.ssid+'\'">'+n.ssid+' ('+n.rssi+' dBm, ch'+n.channel+')</button>'});document.getElementById('networks').innerHTML=h||'<p>No networks found</p>'}).catch(()=>msg('Scan failed','err'))}function connect(e){e.preventDefault();let s=document.getElementById('ssid').value,p=document.getElementById('psk').value;fetch('/api/wifi/connect',{method:'POST',body:JSON.stringify({ssid:s,password:p})}).then(r=>{if(r.ok)msg('Connecting to '+s+'...','ok');else msg('Failed','err')}).catch(()=>msg('Error','err'))}function msg(t,c){let m=document.getElementById('msg');m.textContent=t;m.className=c}</script></body></html>"#;

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
            (*response_ctx).body = SETUP_HTML.as_ptr();
            (*response_ctx).body_len = SETUP_HTML.len();
            (*response_ctx).final_chunk = true;
            (*response_ctx).status = http_status_HTTP_200_OK;
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
