use core::ffi::{c_char, c_int, c_void, CStr};

extern "C" {
    fn shell_backend_uart_get_ptr() -> *const zephyr::raw::shell;
    fn shell_prompt_change(sh: *const zephyr::raw::shell, prompt: *const c_char) -> i32;
    fn shell_start(sh: *const zephyr::raw::shell) -> i32;
    fn z_shell_print_prompt_and_cmd(sh: *const zephyr::raw::shell);
    fn shell_execute_cmd(sh: *const zephyr::raw::shell, cmd: *const c_char) -> i32;
    fn shell_get_return_value(sh: *const zephyr::raw::shell) -> i32;
    pub fn gmtime_r(timer: *const i64, result: *mut Tm) -> *mut Tm;
}

pub fn last_return_value() -> i32 {
    let sh = unsafe { shell_backend_uart_get_ptr() };
    if sh.is_null() {
        return 0;
    }
    unsafe { shell_get_return_value(sh) }
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

pub fn set_prompt(prompt: &CStr) -> zephyr::Result<()> {
    let sh = unsafe { shell_backend_uart_get_ptr() };
    if sh.is_null() {
        return zephyr::error::to_result_void(-19);
    }
    zephyr::error::to_result_void(unsafe { shell_prompt_change(sh, prompt.as_ptr()) })
}

pub fn start() -> zephyr::Result<()> {
    let sh = unsafe { shell_backend_uart_get_ptr() };
    if sh.is_null() {
        return zephyr::error::to_result_void(-19);
    }
    zephyr::error::to_result_void(unsafe { shell_start(sh) })
}

pub fn redraw_prompt() {
    let sh = unsafe { shell_backend_uart_get_ptr() };
    if sh.is_null() {
        return;
    }
    unsafe { z_shell_print_prompt_and_cmd(sh) };
}

pub fn terminal_width() -> u16 {
    let sh = unsafe { shell_backend_uart_get_ptr() };
    if sh.is_null() {
        return 80;
    }
    unsafe { (*(*sh).ctx).vt100_ctx.cons.terminal_wid }
}

pub fn probe_terminal_size() {
    let sh = unsafe { shell_backend_uart_get_ptr() };
    if sh.is_null() {
        return;
    }
    unsafe { shell_execute_cmd(sh, c"resize".as_ptr()) };
}

pub mod theme {
    use crate::icons;

    pub const OS_ICON: &str = icons::NF_MD_KITE;
    pub const OS_FG: &str = "\x1b[38;2;0;0;0m";
    pub const OS_BG: &str = "\x1b[48;2;220;200;150m";
    pub const OS_BG_AS_FG: &str = "\x1b[38;2;220;200;150m";

    pub const HOME_ICON: &str = icons::NF_FA_HOME;
    pub const ROOT_ICON: &str = icons::NF_FA_LOCK;
    pub const FOLDER_ICON: &str = icons::NF_FA_FOLDER_OPEN;
    pub const DIR_FG: &str = "\x1b[38;2;0;0;0m";
    pub const DIR_BG: &str = "\x1b[48;2;142;122;181m";
    pub const DIR_BG_AS_FG: &str = "\x1b[38;2;142;122;181m";

    pub const ARCH_ICON: &str = icons::NF_MD_ARCH;
    pub const ARCH_LABEL: &str = zephyr::kconfig::CONFIG_ARCH;
    pub const ARCH_FG: &str = "\x1b[38;2;0;0;0m";
    pub const ARCH_BG: &str = "\x1b[48;2;229;177;83m";
    pub const ARCH_BG_AS_FG: &str = "\x1b[38;2;229;177;83m";

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
