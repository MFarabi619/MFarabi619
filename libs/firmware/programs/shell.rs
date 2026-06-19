use core::ffi::{c_char, c_int, CStr};

// zephyr::raw::shell is opaque from bindgen (its k_spinlock member has no fields), so rustc warns
// improper_ctypes on every signature here even though we treat the pointer as a handle.
#[allow(improper_ctypes)]
extern "C" {
    fn shell_backend_uart_get_ptr() -> *const zephyr::raw::shell;
    fn shell_prompt_change(sh: *const zephyr::raw::shell, prompt: *const c_char) -> i32;
    fn z_shell_print_prompt_and_cmd(sh: *const zephyr::raw::shell);
    fn shell_execute_cmd(sh: *const zephyr::raw::shell, cmd: *const c_char) -> i32;
    fn shell_get_return_value(sh: *const zephyr::raw::shell) -> i32;
}

extern "C" {
    pub fn gmtime_r(timer: *const i64, result: *mut Tm) -> *mut Tm;
    pub fn sys_clock_gettime(clock_id: c_int, tp: *mut Timespec) -> c_int;
    #[cfg(CONFIG_FILE_SYSTEM_SHELL)]
    fn fs_shell_get_cwd() -> *const c_char;
}

#[repr(C)]
#[derive(Default)]
pub struct Timespec {
    pub tv_sec: i64,
    pub tv_nsec: i64,
}

#[repr(C)]
#[derive(Default)]
pub struct Tm {
    pub tm_sec: c_int,
    pub tm_min: c_int,
    pub tm_hour: c_int,
    pub tm_mday: c_int,
    pub tm_mon: c_int,
    pub tm_year: c_int,
    pub tm_wday: c_int,
    pub tm_yday: c_int,
    pub tm_isdst: c_int,
}

fn with_shell<Output>(
    default: Output,
    action: impl FnOnce(*const zephyr::raw::shell) -> Output,
) -> Output {
    let shell_handle = unsafe { shell_backend_uart_get_ptr() };
    if shell_handle.is_null() {
        default
    } else {
        action(shell_handle)
    }
}

pub fn cwd() -> alloc::string::String {
    #[cfg(CONFIG_FILE_SYSTEM_SHELL)]
    {
        use alloc::string::ToString;
        unsafe { CStr::from_ptr(fs_shell_get_cwd()).to_string_lossy().to_string() }
    }
    #[cfg(not(CONFIG_FILE_SYSTEM_SHELL))]
    alloc::string::String::from("/")
}

#[cfg(CONFIG_FILE_SYSTEM_SHELL)]
#[no_mangle]
extern "C" fn fs_shell_on_cwd_changed() {
    let prompt_text = prompt::build_prompt();
    let _ = set_prompt(prompt_text.as_c_str());
}

pub fn execute(command: &str) -> i32 {
    let Ok(command_cstring) = alloc::ffi::CString::new(command) else {
        return -22;
    };
    with_shell(-19, |shell_handle| unsafe {
        shell_execute_cmd(shell_handle, command_cstring.as_ptr())
    })
}

pub fn last_return_value() -> i32 {
    with_shell(0, |shell_handle| unsafe { shell_get_return_value(shell_handle) })
}

pub fn set_prompt(prompt: &CStr) -> zephyr::Result<()> {
    with_shell(zephyr::error::to_result_void(-19), |shell_handle| {
        zephyr::error::to_result_void(unsafe {
            shell_prompt_change(shell_handle, prompt.as_ptr())
        })
    })
}

pub fn redraw_prompt() {
    with_shell((), |shell_handle| unsafe {
        z_shell_print_prompt_and_cmd(shell_handle);
    })
}

pub fn terminal_width() -> u16 {
    with_shell(80, |shell_handle| unsafe {
        (*(*shell_handle).ctx).vt100_ctx.cons.terminal_wid
    })
}

pub fn probe_terminal_size() {
    with_shell((), |shell_handle| unsafe {
        shell_execute_cmd(shell_handle, c"resize".as_ptr());
    })
}

pub fn initialize() -> zephyr::Result<()> {
    zephyr::time::sleep(zephyr::time::Duration::millis_at_least(200));
    probe_terminal_size();
    #[cfg(CONFIG_SDMMC_STACK)]
    execute("fs cd /SD:");
    let prompt_text = prompt::build_prompt();
    set_prompt(prompt_text.as_c_str())?;
    redraw_prompt();
    Ok(())
}

pub mod theme {
    use super::icons;

    pub const OS_ICON: &str = icons::NF_MD_KITE;
    pub const OS_FG: &str = "\x1b[38;2;0;0;0m";
    pub const OS_BG: &str = "\x1b[48;2;220;200;150m";
    pub const OS_BG_AS_FG: &str = "\x1b[38;2;220;200;150m";

    pub const HOME_ICON: &str = icons::NF_FA_HOME;
    pub const ROOT_ICON: &str = icons::NF_FA_LOCK;
    pub const FOLDER_ICON: &str = icons::NF_FA_FOLDER_OPEN;
    pub const DIR_FG: &str = "\x1b[1;38;2;0;0;0m";
    pub const DIR_BG: &str = "\x1b[48;2;142;122;181m";
    pub const DIR_BG_AS_FG: &str = "\x1b[38;2;142;122;181m";

    pub const ARCH_ICON: &str = icons::NF_MD_ARCH;
    pub const ARCH_LABEL: &str = zephyr::kconfig::CONFIG_ARCH;
    pub const ARCH_FG: &str = "\x1b[38;2;0;0;0m";
    pub const ARCH_BG: &str = "\x1b[48;2;229;177;83m";
    pub const ARCH_BG_AS_FG: &str = "\x1b[38;2;229;177;83m";

    pub const HOST_ICON: &str = icons::NF_FA_SERVER;
    pub const HOST_LABEL: &str = zephyr::kconfig::CONFIG_BOARD;
    pub const HOST_FG: &str = "\x1b[38;2;229;177;83m";

    pub const STATUS_OK_FG: &str = "\x1b[1;38;2;46;204;113m";
    pub const STATUS_OK_GLYPH: &str = "\u{2713}";
    pub const STATUS_ERR_FG: &str = "\x1b[1;38;2;231;76;60m";
    pub const STATUS_ERR_GLYPH: &str = "\u{2717}";

    pub const CTX_FG: &str = "\x1b[38;2;229;177;83m";
    pub const CTX_BG: &str = "\x1b[48;2;30;30;30m";
    pub const CTX_BG_AS_FG: &str = "\x1b[38;2;30;30;30m";

    pub const RAM_ICON: &str = icons::NF_MD_RAM;
    pub const RAM_FG: &str = "\x1b[38;2;0;0;0m";
    pub const RAM_BG: &str = "\x1b[48;2;229;177;83m";
    pub const RAM_BG_AS_FG: &str = "\x1b[38;2;229;177;83m";

    pub const CLOCK_ICON: &str = icons::NF_FA_CLOCK;
    pub const CLOCK_FG: &str = "\x1b[38;2;0;0;0m";
    pub const CLOCK_BG: &str = "\x1b[48;2;220;200;150m";
    pub const CLOCK_BG_AS_FG: &str = "\x1b[38;2;220;200;150m";

    pub const LEFT_SEGMENT_SEPARATOR: &str = icons::NF_PLE_LEFT_HARD;
    pub const RIGHT_SEGMENT_SEPARATOR: &str = icons::NF_PLE_RIGHT_HARD;
    pub const RIGHT_SUBSEGMENT_SEPARATOR: &str = icons::NF_PLE_RIGHT_SOFT;

    pub const FRAME_TOP_LEFT: &str = "\u{256d}\u{2500}";
    pub const FRAME_TOP_RIGHT: &str = "\u{2500}\u{256e}";
    pub const FRAME_BOT_LEFT: &str = "\u{2570}\u{2500}";
    pub const FRAME_LINE: char = '\u{2500}';
    pub const FRAME: &str = "\x1b[2m";
    pub const RESET: &str = "\x1b[0m";
}

pub mod prompt {
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
}

mod icons {
    // Centralized Nerd Font glyph registry.
    // Names match the Nerd Font cheat sheet: https://www.nerdfonts.com/cheat-sheet
    // Format: NF_{source}_{name} in SCREAMING_SNAKE_CASE.
    #![allow(dead_code)]

    pub const NF_FA_FILE:         &str = "\u{f15b}";
    pub const NF_FA_FILE_TEXT:    &str = "\u{f15c}";
    pub const NF_FA_FILE_IMAGE:   &str = "\u{f1c5}";
    pub const NF_FA_FOLDER:       &str = "\u{f07b}";
    pub const NF_FA_FOLDER_OPEN:  &str = "\u{f07c}";

    pub const NF_FA_HOME:         &str = "\u{f015}";
    pub const NF_FA_LOCK:         &str = "\u{f023}";
    pub const NF_FA_CLOCK:        &str = "\u{f017}";
    pub const NF_FA_DATABASE:     &str = "\u{f1c0}";
    pub const NF_FA_GLOBE:        &str = "\u{f0ac}";
    pub const NF_FA_SERVER:       &str = "\u{f233}";
    pub const NF_FA_PLUG:         &str = "\u{f1e6}";
    pub const NF_FA_WIFI:         &str = "\u{f1eb}";
    pub const NF_FA_COG:          &str = "\u{f085}";
    pub const NF_FA_BOLT:         &str = "\u{f0e7}";
    pub const NF_FA_HDD:          &str = "\u{f0a0}";
    pub const NF_FA_LEAF:         &str = "\u{f06c}";
    pub const NF_FA_THERMOMETER:  &str = "\u{f2c9}";
    pub const NF_FA_TINT:         &str = "\u{f043}";
    pub const NF_FA_SITEMAP:      &str = "\u{f1e0}";
    pub const NF_FA_MICROCHIP:    &str = "\u{f2db}";
    pub const NF_FA_SIGNAL:       &str = "\u{f2c8}";
    pub const NF_FA_DOWNLOAD:     &str = "\u{f498}";
    pub const NF_FA_TERMINAL:     &str = "\u{f120}";
    pub const NF_FA_DESKTOP:      &str = "\u{f108}";
    pub const NF_FA_MEMORY:       &str = "\u{f538}";

    pub const NF_DEV_RUST:        &str = "\u{e7a8}";
    pub const NF_DEV_HTML5:       &str = "\u{e736}";
    pub const NF_DEV_JAVASCRIPT:  &str = "\u{e74e}";
    pub const NF_DEV_CSS3:        &str = "\u{e749}";

    pub const NF_SETI_CONFIG:     &str = "\u{e5fc}";
    pub const NF_SETI_TOML:       &str = "\u{e6b2}";
    pub const NF_SETI_JSON:       &str = "\u{e60b}";
    pub const NF_SETI_MARKDOWN:   &str = "\u{e73e}";
    pub const NF_SETI_ORG:        &str = "\u{e633}";
    pub const NF_SETI_WASM:       &str = "\u{e6a1}";

    pub const NF_LINUX_NIX:       &str = "\u{f313}";

    pub const NF_MD_BINARY:       &str = "\u{f471}";
    pub const NF_MD_ARCH:         &str = "\u{e266}";
    pub const NF_MD_KERNEL:       &str = "\u{e615}";
    pub const NF_MD_PICTURE:      &str = "\u{f02ef}";
    pub const NF_MD_DOCUMENT:     &str = "\u{f09ee}";
    pub const NF_MD_PUBLIC:       &str = "\u{f151f}";
    pub const NF_MD_TEMP:         &str = "\u{f0403}";
    pub const NF_MD_SSH:          &str = "\u{f12c0}";
    pub const NF_MD_RAM:          &str = "\u{f0e4}";
    pub const NF_MD_KITE:         &str = "\u{f1985}";

    pub const NF_PLE_LEFT_HARD:   &str = "\u{e0b0}";
    pub const NF_PLE_RIGHT_HARD:  &str = "\u{e0b2}";
    pub const NF_PLE_LEFT_SOFT:   &str = "\u{e0b1}";
    pub const NF_PLE_RIGHT_SOFT:  &str = "\u{e0b3}";
    pub const NF_PLE_LEFT_ROUND:  &str = "\u{e0b6}";
    pub const NF_PLE_RIGHT_ROUND: &str = "\u{e0b4}";

    pub const DEGREE_SIGN:        &str = "\u{00b0}";
    pub const BOX_HORIZONTAL:     char = '\u{2500}';
}