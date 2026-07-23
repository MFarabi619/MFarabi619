use alloc::vec::Vec;
use core::{
    ffi::c_void,
    sync::atomic::{AtomicU32, Ordering},
};

use log::{error, info};
use zephyr::{
    sys::sync::Semaphore,
    time::{sleep, Duration},
};

extern "C" {
    fn esp_hosted_tx(if_type: u8, if_num: u8, payload: *const u8, len: u16) -> i32;
    fn esp_hosted_rx(if_type: *mut u8, payload: *mut *mut u8, len: *mut u16) -> i32;
    fn esp_hosted_netif_set_mac(mac: *const u8);
    fn esp_hosted_netif_recv(if_type: u8, buf: *const u8, len: u16);
    fn esp_hosted_netif_connected(status: i32);
    fn esp_hosted_netif_disconnected(status: i32);
}

const ESP_STA_IF: u8 = 1;
const ESP_AP_IF: u8 = 2;
const ESP_SERIAL_IF: u8 = 3;

const RPC_TYPE_REQUEST: u64 = 1;
const RPC_TYPE_RESPONSE: u64 = 2;
const RPC_TYPE_EVENT: u64 = 3;

const REQUEST_GET_MAC_ADDRESS: u64 = 257;
const REQUEST_WIFI_SET_MODE: u64 = 260;
const REQUEST_WIFI_INIT: u64 = 278;
const REQUEST_WIFI_START: u64 = 280;
const REQUEST_WIFI_CONNECT: u64 = 282;
const REQUEST_WIFI_DISCONNECT: u64 = 283;
const REQUEST_WIFI_SET_CONFIG: u64 = 284;
const RESPONSE_GET_MAC_ADDRESS: u64 = 513;
const REQUEST_GET_DHCP_DNS_STATUS: u64 = 353;
const RPC_EVENT_WIFI_NO_ARGS: u64 = 773;
const RPC_EVENT_STA_CONNECTED: u64 = 775;
const RPC_EVENT_STA_DISCONNECTED: u64 = 776;

const ENVELOPE_FIELD_MESSAGE_TYPE: u32 = 1;
const ENVELOPE_FIELD_MESSAGE_ID: u32 = 2;
const ENVELOPE_FIELD_UID: u32 = 3;
const MAC_FIELD_ADDRESS: u32 = 1;
const EVENT_FIELD_ID: u32 = 2;
const DISCONNECT_FIELD_REASON: u32 = 4;
const FIRST_PAYLOAD_FIELD: u64 = 256;

const WIRE_VARINT: u8 = 0;
const WIRE_FIXED64: u8 = 1;
const WIRE_LENGTH_DELIMITED: u8 = 2;
const WIRE_FIXED32: u8 = 5;

const WIFI_MODE_STA: u64 = 1;
const WIFI_AUTH_WPA2_PSK: u64 = 3;
const WIFI_EVENT_STA_CONNECTED: u64 = 4;
const WIFI_EVENT_STA_DISCONNECTED: u64 = 5;

const TLV_ENDPOINT_NAME: u8 = 0x01;
const TLV_DATA: u8 = 0x02;
const TLV_HEADER_LEN: usize = 3;
const RPC_ENDPOINT: &[u8] = b"RPCRsp";

const RPC_TIMEOUT_MS: u64 = 5000;
const RESPONSE_POLL_INTERVAL_MS: u64 = 100;
const RX_POLL_INTERVAL_MS: u64 = 5;
const STARTUP_DRAIN_ITERATIONS: usize = 30;
const STARTUP_DRAIN_INTERVAL_MS: u64 = 10;
const EIO: i32 = 5;
const ETIMEDOUT: i32 = 116;

fn put_varint(out: &mut Vec<u8>, mut value: u64) {
    loop {
        let byte = (value & 0x7f) as u8;
        value >>= 7;
        if value != 0 {
            out.push(byte | 0x80);
        } else {
            out.push(byte);
            return;
        }
    }
}

fn put_tag(out: &mut Vec<u8>, field: u32, wire: u8) {
    put_varint(out, ((field as u64) << 3) | wire as u64);
}

fn put_int(out: &mut Vec<u8>, field: u32, value: u64) {
    if value == 0 {
        return;
    }
    put_tag(out, field, WIRE_VARINT);
    put_varint(out, value);
}

fn put_bytes(out: &mut Vec<u8>, field: u32, bytes: &[u8]) {
    put_tag(out, field, WIRE_LENGTH_DELIMITED);
    put_varint(out, bytes.len() as u64);
    out.extend_from_slice(bytes);
}

fn push_tlv_header(out: &mut Vec<u8>, tag: u8, len: usize) {
    out.push(tag);
    out.push((len & 0xff) as u8);
    out.push(((len >> 8) & 0xff) as u8);
}

fn payload_wifi_mode() -> Vec<u8> {
    let mut payload = Vec::new();
    put_int(&mut payload, 1, WIFI_MODE_STA);
    payload
}

fn payload_wifi_init() -> Vec<u8> {
    let mut config = Vec::new();
    put_int(&mut config, 1, 10);
    put_int(&mut config, 2, 32);
    put_int(&mut config, 3, 1);
    put_int(&mut config, 5, 32);
    put_int(&mut config, 8, 1);
    put_int(&mut config, 9, 1);
    put_int(&mut config, 11, 1);
    put_int(&mut config, 13, 6);
    put_int(&mut config, 15, 752);
    put_int(&mut config, 16, 32);
    put_int(&mut config, 17, 121);
    put_int(&mut config, 18, 1);
    put_int(&mut config, 20, 0x1F2F3F4F);

    let mut payload = Vec::new();
    put_bytes(&mut payload, 1, &config);
    payload
}

fn payload_wifi_set_config(ssid: &[u8], psk: &[u8]) -> Vec<u8> {
    // The C6 set_config handler dereferences threshold + pmf_cfg unconditionally; omit
    // either submessage and it NULL-derefs and drops the RPC link.
    let mut threshold = Vec::new();
    put_int(&mut threshold, 2, WIFI_AUTH_WPA2_PSK);

    let mut pmf = Vec::new();
    put_int(&mut pmf, 1, 1);

    let mut sta = Vec::new();
    put_bytes(&mut sta, 1, ssid);
    put_bytes(&mut sta, 2, psk);
    put_bytes(&mut sta, 9, &threshold);
    put_bytes(&mut sta, 10, &pmf);

    let mut config = Vec::new();
    put_bytes(&mut config, 2, &sta);

    let mut payload = Vec::new();
    put_bytes(&mut payload, 2, &config);
    payload
}

fn build_rpc(message_id: u64, uid: u32, payload: &[u8]) -> Vec<u8> {
    let mut message = Vec::new();
    put_int(&mut message, ENVELOPE_FIELD_MESSAGE_TYPE, RPC_TYPE_REQUEST);
    put_int(&mut message, ENVELOPE_FIELD_MESSAGE_ID, message_id);
    put_int(&mut message, ENVELOPE_FIELD_UID, uid as u64);
    put_bytes(&mut message, message_id as u32, payload);
    message
}

enum Field<'a> {
    Varint(u64),
    Bytes(&'a [u8]),
}

struct Reader<'a> {
    buf: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn new(buf: &'a [u8]) -> Self {
        Self { buf, pos: 0 }
    }

    fn read_varint(&mut self) -> Option<u64> {
        let mut value = 0u64;
        let mut shift = 0;
        while self.pos < self.buf.len() && shift < 64 {
            let byte = self.buf[self.pos];
            self.pos += 1;
            value |= ((byte & 0x7f) as u64) << shift;
            if byte & 0x80 == 0 {
                return Some(value);
            }
            shift += 7;
        }
        None
    }

    fn next(&mut self) -> Option<(u32, Field<'a>)> {
        loop {
            if self.pos >= self.buf.len() {
                return None;
            }
            let tag = self.read_varint()?;
            let field = (tag >> 3) as u32;
            match (tag & 7) as u8 {
                WIRE_VARINT => return Some((field, Field::Varint(self.read_varint()?))),
                WIRE_LENGTH_DELIMITED => {
                    let len = self.read_varint()? as usize;
                    if self.pos + len > self.buf.len() {
                        return None;
                    }
                    let bytes = &self.buf[self.pos..self.pos + len];
                    self.pos += len;
                    return Some((field, Field::Bytes(bytes)));
                }
                WIRE_FIXED32 => {
                    if self.pos + 4 > self.buf.len() {
                        return None;
                    }
                    self.pos += 4;
                }
                WIRE_FIXED64 => {
                    if self.pos + 8 > self.buf.len() {
                        return None;
                    }
                    self.pos += 8;
                }
                _ => return None,
            }
        }
    }
}

struct Decoded<'a> {
    message_type: u64,
    message_id: u64,
    uid: u32,
    payload: &'a [u8],
}

fn strip_tlv(frame: &[u8]) -> Option<&[u8]> {
    if frame.len() < TLV_HEADER_LEN || frame[0] != TLV_ENDPOINT_NAME {
        return None;
    }
    let endpoint_len = frame[1] as usize | ((frame[2] as usize) << 8);
    let mut pos = TLV_HEADER_LEN + endpoint_len;
    if frame.len() < pos + TLV_HEADER_LEN || frame[pos] != TLV_DATA {
        return None;
    }
    let protobuf_len = frame[pos + 1] as usize | ((frame[pos + 2] as usize) << 8);
    pos += TLV_HEADER_LEN;
    if frame.len() < pos + protobuf_len {
        return None;
    }
    Some(&frame[pos..pos + protobuf_len])
}

fn decode_rpc(protobuf: &[u8]) -> Decoded<'_> {
    let mut reader = Reader::new(protobuf);
    let mut decoded = Decoded {
        message_type: 0,
        message_id: 0,
        uid: 0,
        payload: &[],
    };
    while let Some((field, value)) = reader.next() {
        match (field, value) {
            (ENVELOPE_FIELD_MESSAGE_TYPE, Field::Varint(v)) => decoded.message_type = v,
            (ENVELOPE_FIELD_MESSAGE_ID, Field::Varint(v)) => decoded.message_id = v,
            (ENVELOPE_FIELD_UID, Field::Varint(v)) => decoded.uid = v as u32,
            (f, Field::Bytes(b)) if f as u64 >= FIRST_PAYLOAD_FIELD => decoded.payload = b,
            _ => {}
        }
    }
    decoded
}

fn extract_mac(payload: &[u8]) -> Option<[u8; 6]> {
    let mut reader = Reader::new(payload);
    while let Some((field, value)) = reader.next() {
        if let (MAC_FIELD_ADDRESS, Field::Bytes(b)) = (field, value) {
            if b.len() == 6 {
                let mut mac = [0u8; 6];
                mac.copy_from_slice(b);
                return Some(mac);
            }
        }
    }
    None
}

fn next_uid() -> u32 {
    static UID: AtomicU32 = AtomicU32::new(1);
    UID.fetch_add(1, Ordering::Relaxed)
}

fn rpc_send(message_id: u64, payload: &[u8]) -> Result<u32, i32> {
    let uid = next_uid();
    let protobuf = build_rpc(message_id, uid, payload);

    let mut frame = Vec::with_capacity(2 * TLV_HEADER_LEN + RPC_ENDPOINT.len() + protobuf.len());
    push_tlv_header(&mut frame, TLV_ENDPOINT_NAME, RPC_ENDPOINT.len());
    frame.extend_from_slice(RPC_ENDPOINT);
    push_tlv_header(&mut frame, TLV_DATA, protobuf.len());
    frame.extend_from_slice(&protobuf);

    let ret = unsafe { esp_hosted_tx(ESP_SERIAL_IF, 0, frame.as_ptr(), frame.len() as u16) };
    if ret != 0 {
        return Err(ret);
    }
    Ok(uid)
}

static RPC_CALL_LOCK: Semaphore = Semaphore::new(1, 1);
static RESPONSE_SEMAPHORE: Semaphore = Semaphore::new(0, 1);
static RESPONSE_UID: AtomicU32 = AtomicU32::new(0);
static mut RESPONSE_PAYLOAD: [u8; 256] = [0; 256];
static RESPONSE_PAYLOAD_LEN: AtomicU32 = AtomicU32::new(0);

fn rpc_call_awaiting(message_id: u64, payload: &[u8]) -> Result<(), i32> {
    RESPONSE_SEMAPHORE.reset();
    let uid = rpc_send(message_id, payload)?;
    for _ in 0..(RPC_TIMEOUT_MS / RESPONSE_POLL_INTERVAL_MS) {
        if RESPONSE_SEMAPHORE
            .take(Duration::millis(RESPONSE_POLL_INTERVAL_MS))
            .is_ok()
            && RESPONSE_UID.load(Ordering::SeqCst) == uid
        {
            return Ok(());
        }
    }
    Err(-ETIMEDOUT)
}

fn rpc_call_polling(message_id: u64, payload: &[u8]) -> Result<Option<[u8; 6]>, i32> {
    let uid = rpc_send(message_id, payload)?;
    for _ in 0..(RPC_TIMEOUT_MS / RX_POLL_INTERVAL_MS) {
        let mut if_type = 0u8;
        let mut ptr: *mut u8 = core::ptr::null_mut();
        let mut len = 0u16;
        let ret = unsafe { esp_hosted_rx(&mut if_type, &mut ptr, &mut len) };
        if ret <= 0 || ptr.is_null() {
            sleep(Duration::millis(RX_POLL_INTERVAL_MS));
            continue;
        }
        if if_type != ESP_SERIAL_IF {
            continue;
        }
        let frame = unsafe { core::slice::from_raw_parts(ptr, len as usize) };
        let Some(protobuf) = strip_tlv(frame) else {
            continue;
        };
        let decoded = decode_rpc(protobuf);
        if decoded.message_type == RPC_TYPE_RESPONSE && decoded.uid == uid {
            let mac = if decoded.message_id == RESPONSE_GET_MAC_ADDRESS {
                extract_mac(decoded.payload)
            } else {
                None
            };
            return Ok(mac);
        }
    }
    Err(-ETIMEDOUT)
}

fn handle_event(decoded: &Decoded) {
    match decoded.message_id {
        RPC_EVENT_WIFI_NO_ARGS => {
            let mut event_id = 0u64;
            let mut reader = Reader::new(decoded.payload);
            while let Some((field, value)) = reader.next() {
                if let (EVENT_FIELD_ID, Field::Varint(v)) = (field, value) {
                    event_id = v;
                }
            }
            info!("wifi event id {event_id}");
            if event_id == WIFI_EVENT_STA_CONNECTED {
                unsafe { esp_hosted_netif_connected(0) };
            } else if event_id == WIFI_EVENT_STA_DISCONNECTED {
                unsafe { esp_hosted_netif_disconnected(0) };
            }
        }
        RPC_EVENT_STA_CONNECTED => unsafe { esp_hosted_netif_connected(0) },
        RPC_EVENT_STA_DISCONNECTED => {
            let mut reason = 0u64;
            let mut reader = Reader::new(decoded.payload);
            while let Some((field, value)) = reader.next() {
                if let (DISCONNECT_FIELD_REASON, Field::Varint(v)) = (field, value) {
                    reason = v;
                }
            }
            info!("STA disconnected, reason {reason}");
            unsafe { esp_hosted_netif_disconnected(reason as i32) };
        }
        _ => {}
    }
}

#[no_mangle]
pub extern "C" fn esp_hosted_wifi_setup() -> i32 {
    for _ in 0..STARTUP_DRAIN_ITERATIONS {
        let mut if_type = 0u8;
        let mut ptr: *mut u8 = core::ptr::null_mut();
        let mut len = 0u16;
        unsafe { esp_hosted_rx(&mut if_type, &mut ptr, &mut len) };
        sleep(Duration::millis(STARTUP_DRAIN_INTERVAL_MS));
    }

    if rpc_call_polling(REQUEST_WIFI_INIT, &payload_wifi_init()).is_err() {
        error!("wifi init failed");
        return -EIO;
    }
    if rpc_call_polling(REQUEST_WIFI_SET_MODE, &payload_wifi_mode()).is_err() {
        error!("set mode failed");
        return -EIO;
    }
    if rpc_call_polling(REQUEST_WIFI_START, &[]).is_err() {
        error!("wifi start failed");
        return -EIO;
    }
    match rpc_call_polling(REQUEST_GET_MAC_ADDRESS, &payload_wifi_mode()) {
        Ok(Some(mac)) => {
            unsafe { esp_hosted_netif_set_mac(mac.as_ptr()) };
            info!(
                "STA MAC {:02x}:{:02x}:{:02x}:{:02x}:{:02x}:{:02x}",
                mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]
            );
        }
        _ => {
            error!("get mac failed");
            return -EIO;
        }
    }
    0
}

#[no_mangle]
pub extern "C" fn esp_hosted_wifi_event_task(_a: *mut c_void, _b: *mut c_void, _c: *mut c_void) {
    loop {
        let mut if_type = 0u8;
        let mut ptr: *mut u8 = core::ptr::null_mut();
        let mut len = 0u16;
        let ret = unsafe { esp_hosted_rx(&mut if_type, &mut ptr, &mut len) };
        if ret <= 0 || ptr.is_null() {
            sleep(Duration::millis(RX_POLL_INTERVAL_MS));
            continue;
        }
        if if_type == ESP_STA_IF || if_type == ESP_AP_IF {
            unsafe { esp_hosted_netif_recv(if_type, ptr, len) };
            continue;
        }
        if if_type != ESP_SERIAL_IF {
            continue;
        }
        let frame = unsafe { core::slice::from_raw_parts(ptr, len as usize) };
        let Some(protobuf) = strip_tlv(frame) else {
            continue;
        };
        let decoded = decode_rpc(protobuf);
        if decoded.message_type == RPC_TYPE_EVENT {
            handle_event(&decoded);
        } else if decoded.message_type == RPC_TYPE_RESPONSE {
            let n = decoded.payload.len().min(256);
            unsafe { RESPONSE_PAYLOAD[..n].copy_from_slice(&decoded.payload[..n]) };
            RESPONSE_PAYLOAD_LEN.store(n as u32, Ordering::SeqCst);
            RESPONSE_UID.store(decoded.uid, Ordering::SeqCst);
            RESPONSE_SEMAPHORE.give();
        }
    }
}

#[no_mangle]
pub extern "C" fn esp_hosted_wifi_connect(
    ssid: *const u8,
    ssid_len: u16,
    psk: *const u8,
    psk_len: u16,
) -> i32 {
    let ssid = unsafe { core::slice::from_raw_parts(ssid, ssid_len as usize) };
    let psk = unsafe { core::slice::from_raw_parts(psk, psk_len as usize) };

    if rpc_call_awaiting(REQUEST_WIFI_SET_CONFIG, &payload_wifi_set_config(ssid, psk)).is_err() {
        error!("set_config failed");
        return -EIO;
    }
    if rpc_call_awaiting(REQUEST_WIFI_CONNECT, &[]).is_err() {
        error!("connect failed");
        return -EIO;
    }
    0
}

#[no_mangle]
pub extern "C" fn esp_hosted_wifi_query_dhcp() -> i32 {
    if rpc_call_awaiting(REQUEST_GET_DHCP_DNS_STATUS, &[]).is_err() {
        error!("dhcp status query failed");
        return -EIO;
    }
    let n = RESPONSE_PAYLOAD_LEN.load(Ordering::SeqCst) as usize;
    let payload: &[u8] = unsafe { &RESPONSE_PAYLOAD[..n] };
    let mut link_up = 0u64;
    let mut dhcp_up = 0u64;
    let mut ip = Vec::new();
    let mut netmask = Vec::new();
    let mut gateway = Vec::new();
    let mut dns = Vec::new();
    let mut reader = Reader::new(payload);
    while let Some((field, value)) = reader.next() {
        match (field, value) {
            (2, Field::Varint(v)) => link_up = v,
            (3, Field::Varint(v)) => dhcp_up = v,
            (4, Field::Bytes(b)) => ip = b.to_vec(),
            (5, Field::Bytes(b)) => netmask = b.to_vec(),
            (6, Field::Bytes(b)) => gateway = b.to_vec(),
            (8, Field::Bytes(b)) => dns = b.to_vec(),
            _ => {}
        }
    }
    info!(
        "slave dhcp: link_up={link_up} dhcp_up={dhcp_up} ip={} nm={} gw={} dns={}",
        core::str::from_utf8(&ip).unwrap_or("?"),
        core::str::from_utf8(&netmask).unwrap_or("?"),
        core::str::from_utf8(&gateway).unwrap_or("?"),
        core::str::from_utf8(&dns).unwrap_or("?")
    );
    0
}

#[no_mangle]
pub extern "C" fn esp_hosted_wifi_disconnect() -> i32 {
    if rpc_call_awaiting(REQUEST_WIFI_DISCONNECT, &[]).is_err() {
        return -EIO;
    }
    0
}
