use alloc::string::String as AllocString;
use core::fmt::Write;

use embassy_time::Instant;

use crate::services::identity;

use super::{
    path::{display_cwd, home_dir},
    terminal_width,
};

unsafe extern "C" {
    #[link_name = "esp_app_desc"]
    static ESP_APP_DESC: esp_bootloader_esp_idf::EspAppDesc;
}

pub mod theme {
    use crate::console::icons;

    pub const OS_ICON: &str = icons::NF_FA_MICROCHIP;
    pub const OS_FOREGROUND: &str = "\x1b[30m";
    pub const OS_BACKGROUND: &str = "\x1b[44m";
    pub const OS_BG_AS_FG: &str = "\x1b[34m";

    pub const HOME_ICON: &str = icons::NF_FA_HOME;
    pub const ROOT_ICON: &str = icons::NF_FA_LOCK;
    pub const FOLDER_ICON: &str = icons::NF_FA_FOLDER_OPEN;
    pub const DIR_FOREGROUND: &str = "\x1b[30m";
    pub const DIR_BACKGROUND: &str = "\x1b[45m";
    pub const DIR_BG_AS_FG: &str = "\x1b[35m";

    pub const ARCH_ICON: &str = icons::NF_MD_ARCH;
    pub const ARCH_LABEL: &str = "xtensa";
    pub const ARCH_BACKGROUND: &str = "\x1b[43m";

    pub const CONTEXT_FOREGROUND: &str = "\x1b[33m";
    pub const CONTEXT_BACKGROUND: &str = "\x1b[40m";
    pub const CONTEXT_BG_AS_FG: &str = "\x1b[30m";

    pub const RAM_ICON: &str = icons::NF_MD_RAM;
    pub const RAM_FOREGROUND: &str = "\x1b[30m";
    pub const RAM_BACKGROUND: &str = "\x1b[43m";

    pub const CLOCK_ICON: &str = icons::NF_FA_CLOCK;
    pub const CLOCK_FOREGROUND: &str = "\x1b[30m";
    pub const CLOCK_BACKGROUND: &str = "\x1b[47m";
    pub const CLOCK_BG_AS_FG: &str = "\x1b[37m";

    pub const LEFT_SEGMENT_SEPARATOR: &str = icons::NF_PLE_LEFT_HARD;
    pub const RIGHT_SEGMENT_SEPARATOR: &str = icons::NF_PLE_RIGHT_HARD;
    pub const RIGHT_SUBSEGMENT_SEPARATOR: &str = icons::NF_PLE_RIGHT_SOFT;

    pub const FRAME_TOP_LEFT: &str = "╭─";
    pub const FRAME_TOP_RIGHT: &str = "─╮";
    pub const FRAME_BOT_LEFT: &str = "╰─";
    pub const FRAME_LINE: char = '─';
    pub const FRAME_COLOR: &str = "\x1b[2m";
    pub const RESET: &str = "\x1b[0m";
}

fn cwd_glyph(cwd: &str) -> &'static str {
    let home = home_dir();
    if cwd == "/" {
        theme::ROOT_ICON
    } else if cwd == home || cwd.starts_with(home.as_str()) {
        theme::HOME_ICON
    } else {
        theme::FOLDER_ICON
    }
}

pub fn build_prompt(cwd: &str) -> AllocString {
    use crate::time::{get_current_epoch_secs, is_time_synced};

    let mut prompt_buffer = AllocString::new();

    let time_str = if is_time_synced() {
        let epoch = get_current_epoch_secs();
        let local_epoch = (epoch as i64 + crate::config::time::UTC_OFFSET_HOURS * 3600) as u64;
        let secs_of_day = local_epoch % 86400;
        let hour24 = secs_of_day / 3600;
        let minute = (secs_of_day % 3600) / 60;
        let second = secs_of_day % 60;
        let (hour12, ampm) = if hour24 == 0 {
            (12, "AM")
        } else if hour24 < 12 {
            (hour24, "AM")
        } else if hour24 == 12 {
            (12, "PM")
        } else {
            (hour24 - 12, "PM")
        };
        let mut time = AllocString::new();
        let _ = write!(time, "{:02}:{:02}:{:02} {}", hour12, minute, second, ampm);
        time
    } else {
        let uptime = Instant::now().as_secs();
        let mut time = AllocString::new();
        let _ = write!(time, "{}m{}s", uptime / 60, uptime % 60);
        time
    };

    let display = display_cwd(cwd);
    let glyph = cwd_glyph(cwd);

    let mut left = AllocString::new();
    let _ = write!(left, "\x1b[2m{}\x1b[0m", theme::FRAME_TOP_LEFT);
    let _ = write!(
        left,
        "{}{} {} ",
        theme::OS_BACKGROUND,
        theme::OS_FOREGROUND,
        theme::OS_ICON
    );
    let _ = write!(
        left,
        "{}{}{}",
        theme::DIR_BACKGROUND,
        theme::OS_BG_AS_FG,
        theme::LEFT_SEGMENT_SEPARATOR
    );
    let _ = write!(
        left,
        "{}{} {} {} ",
        theme::DIR_BACKGROUND,
        theme::DIR_FOREGROUND,
        glyph,
        display
    );
    let _ = write!(
        left,
        "\x1b[0m{}{}\x1b[0m",
        theme::DIR_BG_AS_FG,
        theme::LEFT_SEGMENT_SEPARATOR
    );

    let heap_used = esp_alloc::HEAP.used();
    let heap_free = esp_alloc::HEAP.free();
    let heap_total = heap_used + heap_free;
    let heap_pct = if heap_total > 0 {
        (heap_used * 100) / heap_total
    } else {
        0
    };

    let mut ram_str = AllocString::new();
    if heap_free >= 1024 * 1024 {
        let _ = write!(ram_str, "{:.1}M", heap_free as f32 / (1024.0 * 1024.0));
    } else {
        let _ = write!(ram_str, "{:.1}K", heap_free as f32 / 1024.0);
    }

    let mut ram_pct_str = AllocString::new();
    let _ = write!(ram_pct_str, "{}%", heap_pct);

    let mut context_str = AllocString::new();
    let _ = write!(
        context_str,
        "{}@{}",
        identity::ssh_user(),
        identity::hostname()
    );

    let mut right = AllocString::new();
    let _ = write!(
        right,
        "{}{}\x1b[0m",
        theme::CONTEXT_BG_AS_FG,
        theme::RIGHT_SEGMENT_SEPARATOR
    );
    let _ = write!(
        right,
        "{}{} {} ",
        theme::CONTEXT_BACKGROUND,
        theme::CONTEXT_FOREGROUND,
        context_str
    );
    let _ = write!(
        right,
        "{}{}{} ",
        theme::RAM_BACKGROUND,
        theme::RAM_FOREGROUND,
        theme::RIGHT_SEGMENT_SEPARATOR
    );
    let _ = write!(
        right,
        "{}{} {} {} {} {} {} {} ",
        theme::RAM_BACKGROUND,
        theme::RAM_FOREGROUND,
        ram_pct_str,
        theme::RAM_ICON,
        ram_str,
        theme::RIGHT_SUBSEGMENT_SEPARATOR,
        theme::ARCH_LABEL,
        theme::ARCH_ICON
    );
    let _ = write!(
        right,
        "{}{}{}\x1b[0m",
        theme::ARCH_BACKGROUND,
        theme::CLOCK_BG_AS_FG,
        theme::RIGHT_SEGMENT_SEPARATOR
    );
    let _ = write!(
        right,
        "{}{} {} {} \x1b[0m",
        theme::CLOCK_BACKGROUND,
        theme::CLOCK_FOREGROUND,
        time_str,
        theme::CLOCK_ICON
    );
    let _ = write!(right, "\x1b[2m{}\x1b[0m", theme::FRAME_TOP_RIGHT);

    let nf_icons_left = 3;
    let nf_icons_right = 6;
    let left_vis = 2 + 1 + display.len() + nf_icons_left * 2 + 4;
    let right_vis = context_str.len()
        + 2
        + ram_pct_str.len()
        + 1
        + ram_str.len()
        + 1
        + theme::ARCH_LABEL.len()
        + time_str.len()
        + 2
        + nf_icons_right * 2
        + 8;
    let fill = (terminal_width() as usize)
        .saturating_sub(left_vis + right_vis)
        .max(1);

    let _ = write!(prompt_buffer, "{}", left);
    let _ = write!(prompt_buffer, "\x1b[2m");
    for _ in 0..fill {
        prompt_buffer.push(theme::FRAME_LINE);
    }
    let _ = write!(prompt_buffer, "\x1b[0m");
    let _ = write!(prompt_buffer, "{}\r\n", right);
    let _ = write!(prompt_buffer, "\x1b[2m{}\x1b[0m ", theme::FRAME_BOT_LEFT);

    prompt_buffer
}

pub fn build_motd(remote: &str) -> AllocString {
    use crate::time;
    use esp_hal::efuse;

    let mut out = AllocString::new();

    let epoch = time::get_current_epoch_secs();
    if epoch > 0 {
        let ts = time::format_iso8601(epoch);
        let _ = write!(out, "Last login: {} from {}\r\n", ts, remote);
    }

    let chip_rev = efuse::chip_revision();
    unsafe {
        let desc = &ESP_APP_DESC;
        let _ = write!(
            out,
            "Microvisor {} (ESP32-S3 rev {}.{}) built {}\r\n",
            desc.version(),
            chip_rev.major,
            chip_rev.minor,
            desc.date(),
        );
    }

    let _ = write!(out, "\r\n");
    let _ = write!(out, "Welcome to Microvisor!\r\n");
    let _ = write!(out, "\r\n");
    let _ = write!(out, "System information:     microfetch\r\n");
    let _ = write!(out, "Hardware sensors:       sensors\r\n");
    let _ = write!(out, "Network interfaces:     ifconfig\r\n");
    let _ = write!(out, "Memory usage:           free\r\n");
    let _ = write!(out, "Disk usage:             df\r\n");
    let _ = write!(out, "\r\n");
    let _ = write!(
        out,
        "Data files are stored on the SD card mounted at /.\r\n"
    );
    let _ = write!(out, "Show the list of available commands:  help\r\n");
    let _ = write!(out, "\r\n");

    out
}
