use alloc::ffi::CString;
use alloc::string::String;
use core::fmt::Write;

use super::{self as shell, theme};

fn dir_icon(cwd: &str) -> &'static str {
    if cwd == "/" {
        theme::ROOT_ICON
    } else {
        theme::FOLDER_ICON
    }
}

fn build_frame() -> String {
    let mut buffer = String::new();

    let cwd = shell::cwd();
    let cwd_icon = dir_icon(&cwd);

    let mut wall_clock = shell::Timespec::default();
    let is_synced = unsafe { shell::sys_clock_gettime(1, &mut wall_clock) } == 0
        && wall_clock.tv_sec > 1_577_836_800;

    let uptime_milliseconds = unsafe { zephyr::raw::k_uptime_get() };
    let uptime_seconds = (uptime_milliseconds.max(0) as u64) / 1000;
    let uptime_minutes = uptime_seconds / 60;
    let uptime_seconds_within_minute = uptime_seconds % 60;

    let _ = write!(buffer, "{}{}{}", theme::FRAME, theme::FRAME_TOP_LEFT, theme::RESET);

    let _ = write!(buffer, "{}{} {} ", theme::OS_BG, theme::OS_FG, theme::OS_ICON);
    let _ = write!(buffer, "{}{}{}", theme::DIR_BG, theme::OS_BG_AS_FG, theme::LEFT_SEGMENT_SEPARATOR);
    let _ = write!(buffer, "{}{} {} {} ", theme::DIR_BG, theme::DIR_FG, cwd_icon, cwd);
    let _ = write!(buffer, "{}{}{}{}", theme::RESET, theme::DIR_BG_AS_FG, theme::LEFT_SEGMENT_SEPARATOR, theme::RESET);

    let left_visible_width = 2
        + 1 + 1 + 1
        + 1
        + 1 + 1 + 1 + cwd.chars().count() + 1
        + 1;
    let status_visible_width = 1 + 1 + 1;
    let host_visible_width = 1 + 1 + 1 + theme::HOST_LABEL.chars().count() + 1;
    let arch_visible_width = 1
        + 1 + theme::ARCH_LABEL.chars().count() + 1
        + 1 + 1;
    let time_visible_width = if is_synced {
        11
    } else if uptime_minutes < 10 {
        5
    } else if uptime_minutes < 100 {
        6
    } else {
        7
    };
    let clock_visible_width = 1 + 1 + time_visible_width + 1 + 1 + 1;
    let right_visible_width =
        status_visible_width + host_visible_width + arch_visible_width + clock_visible_width + 2;
    let fill_width = (shell::terminal_width() as usize)
        .saturating_sub(left_visible_width + right_visible_width)
        .max(1);

    let _ = write!(buffer, "{}", theme::FRAME);
    for _ in 0..fill_width {
        buffer.push(theme::FRAME_LINE);
    }
    let _ = write!(buffer, "{}", theme::RESET);

    let _ = write!(buffer, " {}{}{} ", theme::STATUS_OK_FG, theme::STATUS_OK_GLYPH, theme::RESET);

    let _ = write!(buffer, "{} {} {} {}", theme::HOST_FG, theme::HOST_ICON, theme::HOST_LABEL, theme::RESET);

    let _ = write!(buffer, " {}{}{}", theme::ARCH_BG_AS_FG, theme::RIGHT_SEGMENT_SEPARATOR, theme::RESET);
    let _ = write!(buffer, "{}{} {} {} ", theme::ARCH_BG, theme::ARCH_FG, theme::ARCH_LABEL, theme::ARCH_ICON);

    let _ = write!(buffer, "{}{}{}", theme::ARCH_BG, theme::CLOCK_BG_AS_FG, theme::RIGHT_SEGMENT_SEPARATOR);
    let _ = write!(buffer, "{}{}", theme::CLOCK_BG, theme::CLOCK_FG);
    if is_synced {
        let local_timestamp =
            wall_clock.tv_sec + (zephyr::kconfig::CONFIG_PROMPT_TZ_OFFSET_MINUTES as i64) * 60;
        let mut calendar = shell::Tm::default();
        unsafe { shell::gmtime_r(&local_timestamp, &mut calendar) };
        let (hour_12, meridiem) = match calendar.tm_hour {
            0 => (12, "AM"),
            hour if hour < 12 => (hour, "AM"),
            12 => (12, "PM"),
            hour => (hour - 12, "PM"),
        };
        let _ = write!(
            buffer,
            " {:02}:{:02}:{:02} {} {} {}",
            hour_12, calendar.tm_min, calendar.tm_sec, meridiem, theme::CLOCK_ICON, theme::RESET
        );
    } else {
        let _ = write!(
            buffer,
            " {}m{:02}s {} {}",
            uptime_minutes, uptime_seconds_within_minute, theme::CLOCK_ICON, theme::RESET
        );
    }
    let _ = write!(buffer, "{}{}{}", theme::FRAME, theme::FRAME_TOP_RIGHT, theme::RESET);

    buffer
}

pub fn build_prompt() -> CString {
    let mut buffer = String::from("\r\n");
    buffer.push_str(&build_frame());
    let _ = write!(buffer, "\r\n{}{}{} ", theme::FRAME, theme::FRAME_BOT_LEFT, theme::RESET);
    CString::new(buffer).unwrap()
}
