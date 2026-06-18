pub mod prompt;

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

#[cfg(CONFIG_FILE_SYSTEM_SHELL)]
pub fn cwd() -> alloc::string::String {
    use alloc::string::ToString;
    unsafe { CStr::from_ptr(fs_shell_get_cwd()).to_string_lossy().to_string() }
}

#[cfg(CONFIG_FILE_SYSTEM_SHELL)]
#[no_mangle]
extern "C" fn fs_shell_on_cwd_changed() {
    let prompt_text = prompt::build_prompt();
    let _ = set_prompt(prompt_text.as_c_str());
}

#[cfg(not(CONFIG_FILE_SYSTEM_SHELL))]
pub fn cwd() -> alloc::string::String {
    alloc::string::String::from("/")
}

pub fn execute(cmd: &str) -> i32 {
    let shell_handle = unsafe { shell_backend_uart_get_ptr() };
    if shell_handle.is_null() {
        return -19;
    }
    let Ok(cmd_cstring) = alloc::ffi::CString::new(cmd) else {
        return -22;
    };
    unsafe { shell_execute_cmd(shell_handle, cmd_cstring.as_ptr()) }
}

#[repr(C)]
#[derive(Default)]
pub struct Timespec {
    pub tv_sec: i64,
    pub tv_nsec: i64,
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

pub fn last_return_value() -> i32 {
    let shell_handle = unsafe { shell_backend_uart_get_ptr() };
    if shell_handle.is_null() {
        return 0;
    }
    unsafe { shell_get_return_value(shell_handle) }
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
    let shell_handle = unsafe { shell_backend_uart_get_ptr() };
    if shell_handle.is_null() {
        return zephyr::error::to_result_void(-19);
    }
    zephyr::error::to_result_void(unsafe { shell_prompt_change(shell_handle, prompt.as_ptr()) })
}

pub fn redraw_prompt() {
    let shell_handle = unsafe { shell_backend_uart_get_ptr() };
    if shell_handle.is_null() {
        return;
    }
    unsafe { z_shell_print_prompt_and_cmd(shell_handle) };
}

pub fn terminal_width() -> u16 {
    let shell_handle = unsafe { shell_backend_uart_get_ptr() };
    if shell_handle.is_null() {
        return 80;
    }
    unsafe { (*(*shell_handle).ctx).vt100_ctx.cons.terminal_wid }
}

pub fn probe_terminal_size() {
    let shell_handle = unsafe { shell_backend_uart_get_ptr() };
    if shell_handle.is_null() {
        return;
    }
    unsafe { shell_execute_cmd(shell_handle, c"resize".as_ptr()) };
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
