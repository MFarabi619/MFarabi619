use core::fmt::Write;
use core::sync::atomic::{AtomicBool, AtomicU32, Ordering};

use embassy_time::Instant;
use heapless::String as HeaplessString;

pub const MAX_ISO8601_LEN: usize = 32;

static TIME_SYNCED: AtomicBool = AtomicBool::new(false);
static BOOT_EPOCH_SECS_HI: AtomicU32 = AtomicU32::new(0);
static BOOT_EPOCH_SECS_LO: AtomicU32 = AtomicU32::new(0);
static BOOT_INSTANT_SECS: AtomicU32 = AtomicU32::new(0);

pub fn set_time_synced(epoch_secs: u64) {
    BOOT_EPOCH_SECS_HI.store((epoch_secs >> 32) as u32, Ordering::Release);
    BOOT_EPOCH_SECS_LO.store((epoch_secs & 0xFFFF_FFFF) as u32, Ordering::Release);
    BOOT_INSTANT_SECS.store(Instant::now().as_secs() as u32, Ordering::Release);
    TIME_SYNCED.store(true, Ordering::Release);
}

pub fn is_time_synced() -> bool {
    TIME_SYNCED.load(Ordering::Acquire)
}

pub fn get_current_epoch_secs() -> u64 {
    if !is_time_synced() {
        return 0;
    }

    let hi = BOOT_EPOCH_SECS_HI.load(Ordering::Acquire) as u64;
    let lo = BOOT_EPOCH_SECS_LO.load(Ordering::Acquire) as u64;
    let boot_epoch = (hi << 32) | lo;
    let boot_instant = BOOT_INSTANT_SECS.load(Ordering::Acquire) as u64;
    let now_instant = Instant::now().as_secs();

    boot_epoch.saturating_add(now_instant.saturating_sub(boot_instant))
}

/// Calendar components broken out from a Unix epoch second value.
#[derive(Clone, Copy, Debug)]
pub struct Calendar {
    pub year: u16,
    pub month: u8,
    pub day: u8,
    pub hours: u8,
    pub minutes: u8,
    pub seconds: u8,
}

fn is_leap_year(year: u16) -> bool {
    (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
}

fn days_in_month(year: u16, month_index: usize) -> u8 {
    const COMMON: [u8; 12] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if month_index == 1 && is_leap_year(year) {
        29
    } else {
        COMMON[month_index]
    }
}

/// Convert Unix epoch seconds to a proleptic Gregorian calendar tuple.
pub fn epoch_to_calendar(epoch_secs: u64) -> Calendar {
    let days_since_epoch = epoch_secs / 86400;
    let time_of_day = epoch_secs % 86400;
    let hours = (time_of_day / 3600) as u8;
    let minutes = ((time_of_day % 3600) / 60) as u8;
    let seconds = (time_of_day % 60) as u8;

    let mut remaining_days = days_since_epoch;
    let mut year = 1970u16;
    loop {
        let year_length = if is_leap_year(year) { 366 } else { 365 };
        if remaining_days < year_length {
            break;
        }
        remaining_days -= year_length;
        year += 1;
    }

    let mut month_index = 0usize;
    while month_index < 12 {
        let length = days_in_month(year, month_index) as u64;
        if remaining_days < length {
            break;
        }
        remaining_days -= length;
        month_index += 1;
    }

    Calendar {
        year,
        month: month_index as u8 + 1,
        day: remaining_days as u8 + 1,
        hours,
        minutes,
        seconds,
    }
}

pub fn format_iso8601(epoch_secs: u64) -> HeaplessString<MAX_ISO8601_LEN> {
    if epoch_secs == 0 {
        return HeaplessString::new();
    }

    let calendar = epoch_to_calendar(epoch_secs);

    let mut result = HeaplessString::new();
    let _ = core::write!(
        result,
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        calendar.year,
        calendar.month,
        calendar.day,
        calendar.hours,
        calendar.minutes,
        calendar.seconds
    );

    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn format_iso8601_zero_returns_empty() {
        let result = format_iso8601(0);
        defmt::assert!(result.is_empty());
    }

    #[test]
    fn format_iso8601_known_epoch() {
        let result = format_iso8601(1_700_000_000);
        defmt::assert_eq!(result.as_str(), "2023-11-14T22:13:20Z");
    }

    #[test]
    fn format_iso8601_leap_year() {
        let result = format_iso8601(1_709_337_600);
        defmt::assert_eq!(result.as_str(), "2024-03-02T00:00:00Z");
    }

    #[test]
    fn format_iso8601_epoch_zero() {
        let result = format_iso8601(0);
        defmt::assert!(result.is_empty());
    }

    #[test]
    fn get_current_epoch_secs_returns_zero_when_not_synced() {
        let initial_synced = TIME_SYNCED.load(Ordering::Acquire);
        if !initial_synced {
            defmt::assert_eq!(get_current_epoch_secs(), 0);
        }
    }
}
