use embedded_storage::nor_flash::NorFlash;
use embedded_storage::ReadStorage;
use esp_storage::FlashStorage;

pub const DEFAULT_SSID: &str = env!("WIFI_SSID");
pub const DEFAULT_PASSWORD: &str = env!("WIFI_PSK");

const CREDENTIALS_MAGIC: u32 = 0xCE6A0001;
const CREDENTIALS_OFFSET: usize = 0x1000;
#[allow(dead_code, reason = "used by credential update API endpoint")]
const CREDENTIALS_SECTOR_SIZE: usize = 4096;
const SSID_MAX_LEN: usize = 32;
const PASSWORD_MAX_LEN: usize = 64;

#[repr(C)]
struct CredentialsRecord {
    magic: u32,
    ssid_len: u8,
    password_len: u8,
    ssid: [u8; SSID_MAX_LEN],
    password: [u8; PASSWORD_MAX_LEN],
}

pub struct WifiCredentials {
    pub ssid: heapless::String<SSID_MAX_LEN>,
    pub password: heapless::String<PASSWORD_MAX_LEN>,
}

pub fn default_credentials() -> WifiCredentials {
    WifiCredentials {
        ssid: heapless::String::try_from(DEFAULT_SSID).unwrap(),
        password: heapless::String::try_from(DEFAULT_PASSWORD).unwrap(),
    }
}

pub fn read_from_flash(flash: &mut FlashStorage) -> Option<WifiCredentials> {
    let mut buffer = [0u8; size_of::<CredentialsRecord>()];

    if flash.read(CREDENTIALS_OFFSET as u32, &mut buffer).is_err() {
        return None;
    }

    let record: CredentialsRecord =
        unsafe { core::ptr::read_unaligned(buffer.as_ptr() as *const _) };

    if record.magic != CREDENTIALS_MAGIC {
        return None;
    }

    let ssid_len = record.ssid_len as usize;
    let password_len = record.password_len as usize;

    if ssid_len > SSID_MAX_LEN || password_len > PASSWORD_MAX_LEN || ssid_len == 0 {
        return None;
    }

    let mut ssid = heapless::String::new();
    for &byte in &record.ssid[..ssid_len] {
        if ssid.push(byte as char).is_err() {
            break;
        }
    }

    let mut password = heapless::String::new();
    for &byte in &record.password[..password_len] {
        if password.push(byte as char).is_err() {
            break;
        }
    }

    Some(WifiCredentials { ssid, password })
}

pub fn write_to_flash(flash: &mut FlashStorage, ssid: &str, password: &str) -> bool {
    if ssid.len() > SSID_MAX_LEN || password.len() > PASSWORD_MAX_LEN || ssid.is_empty() {
        return false;
    }

    let mut record = CredentialsRecord {
        magic: CREDENTIALS_MAGIC,
        ssid_len: ssid.len() as u8,
        password_len: password.len() as u8,
        ssid: [0u8; SSID_MAX_LEN],
        password: [0u8; PASSWORD_MAX_LEN],
    };

    record.ssid[..ssid.len()].copy_from_slice(ssid.as_bytes());
    record.password[..password.len()].copy_from_slice(password.as_bytes());

    let mut buffer = [0xFFu8; CREDENTIALS_SECTOR_SIZE];
    let record_bytes = unsafe {
        core::slice::from_raw_parts(
            &record as *const CredentialsRecord as *const u8,
            size_of::<CredentialsRecord>(),
        )
    };
    buffer[..record_bytes.len()].copy_from_slice(record_bytes);

    if NorFlash::erase(
        flash,
        CREDENTIALS_OFFSET as u32,
        (CREDENTIALS_OFFSET + CREDENTIALS_SECTOR_SIZE) as u32,
    )
    .is_err()
    {
        return false;
    }

    if flash.write(CREDENTIALS_OFFSET as u32, &buffer).is_err() {
        return false;
    }

    if let Some(verified) = read_from_flash(flash) {
        verified.ssid.as_str() == ssid && verified.password.as_str() == password
    } else {
        false
    }
}
