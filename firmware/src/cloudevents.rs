use alloc::format;
use alloc::string::String;
use core::ffi::c_char;
use zephyr::raw::{uuid, uuid_generate_v5, uuid_to_string, UUID_STR_LEN};

const APIDAE_NAMESPACE: uuid = uuid {
    val: [
        0x3e, 0x5e, 0x20, 0x5a,
        0x9c, 0x3f,
        0x45, 0x41,
        0x91, 0x75,
        0x81, 0xaa, 0x04, 0xad, 0xef, 0x3d,
    ],
};

fn uuid_v5(input: &[u8]) -> String {
    let mut out = uuid { val: [0u8; 16] };
    let mut text = [0u8; UUID_STR_LEN as usize];

    unsafe {
        if uuid_generate_v5(
            &APIDAE_NAMESPACE,
            input.as_ptr() as *const _,
            input.len(),
            &mut out,
        ) != 0
        {
            return String::from("00000000-0000-0000-0000-000000000000");
        }
        if uuid_to_string(&out, text.as_mut_ptr() as *mut c_char) != 0 {
            return String::from("00000000-0000-0000-0000-000000000000");
        }
    }

    let length = text.iter().position(|&b| b == 0).unwrap_or(36);
    core::str::from_utf8(&text[..length])
        .unwrap_or("00000000-0000-0000-0000-000000000000")
        .into()
}

pub(crate) fn epoch_to_rfc3339(epoch: i64) -> String {
    let days = epoch.div_euclid(86400);
    let secs_of_day = epoch.rem_euclid(86400);

    let z = days + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = (z - era * 146097) as i64;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let mut year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let month = (if mp < 10 { mp + 3 } else { mp - 9 }) as u32;
    if month <= 2 {
        year += 1;
    }

    let hour = (secs_of_day / 3600) as u32;
    let minute = ((secs_of_day % 3600) / 60) as u32;
    let second = (secs_of_day % 60) as u32;

    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        year, month, day, hour, minute, second
    )
}

pub fn envelope(event_type: &str, source: &str, epoch_seconds: i64, data_json: &str) -> String {
    let time = epoch_to_rfc3339(epoch_seconds);
    let id_input = format!("{}:{}:{}", source, event_type, time);
    let id = uuid_v5(id_input.as_bytes());

    format!(
        r#"{{"specversion":"1.0","id":"{}","source":"{}","type":"{}","datacontenttype":"application/json","time":"{}","data":{}}}"#,
        id, source, event_type, time, data_json
    )
}
