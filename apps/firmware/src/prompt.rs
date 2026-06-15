use alloc::ffi::CString;
use alloc::string::String;
use core::fmt::Write;

use crate::shell::{self, theme};

fn build_frame() -> String {
    let mut out = String::new();

    let board = zephyr::kconfig::CONFIG_BOARD;

    let mut ts = zephyr::raw::timespec::default();
    let synced = unsafe { zephyr::raw::sys_clock_gettime(1, &mut ts) } == 0
        && ts.tv_sec > 1_577_836_800;

    let uptime_ms = unsafe { zephyr::raw::k_uptime_get() };
    let uptime_s = (uptime_ms.max(0) as u64) / 1000;
    let mins = uptime_s / 60;
    let secs = uptime_s % 60;

    let _ = write!(out, "{}{}{}", theme::FRAME, theme::FRAME_TOP_LEFT, theme::RESET);

    let _ = write!(out, "{}{} {} ", theme::OS_BG, theme::OS_FG, theme::OS_ICON);
    let _ = write!(out, "{}{}{}", theme::DIR_BG, theme::OS_BG_AS_FG, theme::LEFT_SEGMENT_SEPARATOR);
    let _ = write!(out, "{}{} {} {} ", theme::DIR_BG, theme::DIR_FG, theme::FOLDER_ICON, board);
    let _ = write!(out, "{}{}{}{}", theme::RESET, theme::DIR_BG_AS_FG, theme::LEFT_SEGMENT_SEPARATOR, theme::RESET);

    let left_vis = 2
        + 1 + 1 + 1
        + 1
        + 1 + 1 + 1 + board.chars().count() + 1
        + 1;
    let status_vis = 1 + 1 + 1;
    let arch_vis = 1
        + 1 + theme::ARCH_LABEL.chars().count() + 1
        + 1 + 1;
    let time_chars = if synced {
        11
    } else if mins < 10 {
        5
    } else if mins < 100 {
        6
    } else {
        7
    };
    let clock_vis = 1 + 1 + time_chars + 1 + 1 + 1;
    let right_vis = status_vis + arch_vis + clock_vis + 2;
    let fill = (shell::terminal_width() as usize)
        .saturating_sub(left_vis + right_vis)
        .max(1);

    let _ = write!(out, "{}", theme::FRAME);
    for _ in 0..fill {
        out.push(theme::FRAME_LINE);
    }
    let _ = write!(out, "{}", theme::RESET);

    let _ = write!(out, " {}{}{} ", theme::STATUS_OK_FG, theme::STATUS_OK_GLYPH, theme::RESET);

    let _ = write!(out, "{}{}{}", theme::ARCH_BG_AS_FG, theme::RIGHT_SEGMENT_SEPARATOR, theme::RESET);
    let _ = write!(out, "{}{} {} {} ", theme::ARCH_BG, theme::ARCH_FG, theme::ARCH_LABEL, theme::ARCH_ICON);

    let _ = write!(out, "{}{}{}", theme::ARCH_BG, theme::CLOCK_BG_AS_FG, theme::RIGHT_SEGMENT_SEPARATOR);
    let _ = write!(out, "{}{}", theme::CLOCK_BG, theme::CLOCK_FG);
    if synced {
        let local = ts.tv_sec + (zephyr::kconfig::CONFIG_PROMPT_TZ_OFFSET_MINUTES as i64) * 60;
        let mut tm = shell::Tm::default();
        unsafe { shell::gmtime_r(&local, &mut tm) };
        let (hour12, ampm) = match tm.tm_hour {
            0 => (12, "AM"),
            h if h < 12 => (h, "AM"),
            12 => (12, "PM"),
            h => (h - 12, "PM"),
        };
        let _ = write!(out, " {:02}:{:02}:{:02} {} {} {}", hour12, tm.tm_min, tm.tm_sec, ampm, theme::CLOCK_ICON, theme::RESET);
    } else {
        let _ = write!(out, " {}m{:02}s {} {}", mins, secs, theme::CLOCK_ICON, theme::RESET);
    }
    let _ = write!(out, "{}{}{}", theme::FRAME, theme::FRAME_TOP_RIGHT, theme::RESET);

    out
}

pub fn build_prompt() -> CString {
    let mut out = String::from("\r\n");
    out.push_str(&build_frame());
    let _ = write!(out, "\r\n{}{}{} ", theme::FRAME, theme::FRAME_BOT_LEFT, theme::RESET);
    CString::new(out).unwrap()
}
