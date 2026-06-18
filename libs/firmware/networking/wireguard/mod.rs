use zephyr::error::to_result_void;

use log::warn;

const KEEPALIVE_SECONDS: i32 = 25;

pub const PUBLIC_KEY_B64_SIZE: usize = 45;
pub const ENDPOINT_STR_SIZE: usize = 24;
pub const ALLOWED_CIDR_SIZE: usize = 24;
pub const MAX_PEERS: usize = zephyr::kconfig::CONFIG_WIREGUARD_MAX_PEER as usize;

#[repr(C)]
#[derive(Copy, Clone)]
pub struct PeerSnapshot {
    pub valid: bool,
    pub id: i32,
    pub iface_index: i32,
    pub public_key_b64: [u8; PUBLIC_KEY_B64_SIZE],
    pub endpoint: [u8; ENDPOINT_STR_SIZE],
    pub allowed_cidr: [u8; ALLOWED_CIDR_SIZE],
    pub keepalive_seconds: i32,
    pub last_handshake_age_sec: u32,
    pub last_tx_age_sec: u32,
    pub last_rx_age_sec: u32,
}

#[repr(C)]
pub struct Snapshot {
    pub iface_up: bool,
    pub local_public_key_b64: [u8; PUBLIC_KEY_B64_SIZE],
    pub peer_count: u8,
    pub peers: [PeerSnapshot; MAX_PEERS],
}

extern "C" {
    fn wireguard_set_private_key(b64: *const u8, b64_len: usize) -> i32;
    fn wireguard_log_public_key() -> i32;
    fn wireguard_assign_local_addr(cidr: *const u8, cidr_len: usize) -> i32;
    fn wireguard_bring_interface_up() -> i32;
    fn wireguard_add_peer(
        pubkey: *const u8,
        pubkey_len: usize,
        endpoint: *const u8,
        endpoint_len: usize,
        allowed_cidr: *const u8,
        allowed_cidr_len: usize,
        keepalive_seconds: i32,
    ) -> i32;
    fn wireguard_kickoff_handshake(peer_addr: *const u8, peer_addr_len: usize) -> i32;
    fn wireguard_access_snapshot(snapshot: *mut Snapshot) -> i32;
}

pub fn initialize() -> zephyr::Result<()> {
    let private_key = zephyr::kconfig::CONFIG_WIREGUARD_LOCAL_PRIVATE_KEY;
    if private_key.is_empty() {
        warn!("credentials not configured; skipping");
        return to_result_void(-2);
    }

    let local_cidr = zephyr::kconfig::CONFIG_WIREGUARD_LOCAL_TUNNEL_CIDR;
    to_result_void(unsafe { wireguard_set_private_key(private_key.as_ptr(), private_key.len()) })?;
    let _ = unsafe { wireguard_log_public_key() };
    to_result_void(unsafe { wireguard_assign_local_addr(local_cidr.as_ptr(), local_cidr.len()) })?;
    to_result_void(unsafe { wireguard_bring_interface_up() })?;

    add_peer(
        zephyr::kconfig::CONFIG_WIREGUARD_PEER_PUBLIC_KEY,
        zephyr::kconfig::CONFIG_WIREGUARD_PEER_ENDPOINT,
        zephyr::kconfig::CONFIG_WIREGUARD_PEER_ALLOWED_CIDR,
        KEEPALIVE_SECONDS,
    )?;

    kickoff_handshake(zephyr::kconfig::CONFIG_WIREGUARD_PEER_TUNNEL_ADDR)
}

pub fn add_peer(
    pubkey_b64: &str,
    endpoint: &str,
    allowed_cidr: &str,
    keepalive_seconds: i32,
) -> zephyr::Result<()> {
    to_result_void(unsafe {
        wireguard_add_peer(
            pubkey_b64.as_ptr(),
            pubkey_b64.len(),
            endpoint.as_ptr(),
            endpoint.len(),
            allowed_cidr.as_ptr(),
            allowed_cidr.len(),
            keepalive_seconds,
        )
    })
}

pub fn kickoff_handshake(peer_addr: &str) -> zephyr::Result<()> {
    to_result_void(unsafe { wireguard_kickoff_handshake(peer_addr.as_ptr(), peer_addr.len()) })
}

pub fn access_snapshot() -> Snapshot {
    let mut snapshot: Snapshot = unsafe { core::mem::zeroed() };
    let rc = unsafe { wireguard_access_snapshot(&mut snapshot) };
    if rc != 0 {
        warn!("wireguard snapshot rc={rc}");
    }
    snapshot
}
