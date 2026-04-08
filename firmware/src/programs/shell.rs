//! Shell: SSH server, command dispatch, prompt rendering, and working directory management.

use core::{
    fmt::Write,
    sync::atomic::{AtomicU32, Ordering},
};

use alloc::string::String as AllocString;
use defmt::info;
use ed25519_dalek::SigningKey;
use embassy_net::{Stack, tcp::TcpSocket};
use embassy_time::{Duration, Instant};
use esp_hal::rng::Rng;

use crate::config;
use crate::drivers::crypto::CryptoRng;
use crate::programs::coreutils;
use crate::services::ssh::{AuthMethod, Behavior, Request, SecretKey, Transport};

pub use crate::config::SSH_USER;

unsafe extern "C" {
    #[link_name = "esp_app_desc"]
    static ESP_APP_DESC: esp_bootloader_esp_idf::EspAppDesc;
}

const SSH_PORT: u16 = config::ssh::PORT;
const RX_BUF_SIZE: usize = config::ssh::RX_BUF_SIZE;
const TX_BUF_SIZE: usize = config::ssh::TX_BUF_SIZE;

const CTRL_L: u8 = 0x0c; // Clear screen
const CTRL_P: u8 = 0x10; // History previous
const CTRL_N: u8 = 0x0e; // History next
const CTRL_W: u8 = 0x17; // Delete word backward
const CTRL_U: u8 = 0x15; // Clear line

static TERM_WIDTH: AtomicU32 = AtomicU32::new(80);

/// Set the terminal width from the SSH PTY request.
pub fn set_terminal_width(width: u32) {
    TERM_WIDTH.store(width, Ordering::Relaxed);
}

/// Current terminal width in columns.
pub fn terminal_width() -> u32 {
    TERM_WIDTH.load(Ordering::Relaxed)
}

/// Powerlevel10k-style prompt configuration.
///
/// To customize glyphs, paste Nerd Font characters directly into the const values.
/// Colors use ANSI codes: `30-37` (fg), `40-47` (bg), `90-97` (bright fg).
pub mod prompt {
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
    pub const ARCH_FOREGROUND: &str = "\x1b[30m";
    pub const ARCH_BACKGROUND: &str = "\x1b[43m";
    pub const ARCH_BG_AS_FG: &str = "\x1b[33m";

    pub const CONTEXT_FOREGROUND: &str = "\x1b[33m";
    pub const CONTEXT_BACKGROUND: &str = "\x1b[40m";
    pub const CONTEXT_BG_AS_FG: &str = "\x1b[30m";

    pub const RAM_ICON: &str = icons::NF_MD_RAM;
    pub const RAM_PCT_ICON: &str = icons::NF_FA_MEMORY;
    pub const RAM_FOREGROUND: &str = "\x1b[30m";
    pub const RAM_BACKGROUND: &str = "\x1b[43m";
    pub const RAM_BG_AS_FG: &str = "\x1b[33m";

    pub const CLOCK_ICON: &str = icons::NF_FA_CLOCK;
    pub const CLOCK_FOREGROUND: &str = "\x1b[30m";
    pub const CLOCK_BACKGROUND: &str = "\x1b[47m";
    pub const CLOCK_BG_AS_FG: &str = "\x1b[37m";

    pub const LEFT_SEGMENT_SEPARATOR: &str = icons::NF_PLE_LEFT_HARD;
    pub const RIGHT_SEGMENT_SEPARATOR: &str = icons::NF_PLE_RIGHT_HARD;
    pub const LEFT_SUBSEGMENT_SEPARATOR: &str = icons::NF_PLE_LEFT_SOFT;
    pub const RIGHT_SUBSEGMENT_SEPARATOR: &str = icons::NF_PLE_RIGHT_SOFT;

    pub const FRAME_TOP_LEFT: &str = "╭─";
    pub const FRAME_TOP_RIGHT: &str = "─╮";
    pub const FRAME_BOT_LEFT: &str = "╰─";
    pub const FRAME_BOT_RIGHT: &str = "─╯";
    pub const FRAME_LINE: char = '─';
    pub const FRAME_COLOR: &str = "\x1b[2m";
    pub const RESET: &str = "\x1b[0m";
}

/// Returns `/home/{SSH_USER}`.
pub fn home_dir() -> AllocString {
    let mut h = AllocString::from("/home/");
    h.push_str(SSH_USER);
    h
}

/// Ensure the full directory hierarchy exists on the SD card.
pub fn ensure_filesystem_hierarchy() {
    use crate::filesystems::sd;

    // System directories
    let _ = sd::create_directory("ETC");
    let _ = sd::create_directory("BOOT");
    let _ = sd::create_directory("TMP");

    // Home directory tree
    let _ = sd::create_directory("HOME");
    let home = home_dir();
    let _ = sd::mkdir_at("/home", &home_dir_name_upper());
    let _ = sd::mkdir_at(home.as_str(), ".SSH");
    let _ = sd::mkdir_at(home.as_str(), ".CACHE");
    let _ = sd::mkdir_at(home.as_str(), ".LOCAL");

    // ~/.ssh/auth_key
    let ssh_dir = resolve_path(home.as_str(), ".ssh");
    if sd::read_file_at::<64>(ssh_dir.as_str(), "AUTH_KEY").is_err() {
        let _ = sd::touch_at(ssh_dir.as_str(), "AUTH_KEY");
    }

    // ~/.mshrc — default to running microfetch on login
    if sd::read_file_at::<64>(home.as_str(), ".MSHRC").is_err() {
        let _ = sd::write_file_at(home.as_str(), ".MSHRC", b"microfetch\n");
    }

    // /etc/rc.conf — generated snapshot of runtime configuration
    generate_rc_conf();

    // /boot/loader.conf — generated snapshot of hardware configuration
    generate_loader_conf();
}

fn home_dir_name_upper() -> AllocString {
    let mut s = AllocString::new();
    for c in SSH_USER.chars() {
        s.push(c.to_ascii_uppercase());
    }
    s
}

fn generate_rc_conf() {
    use crate::filesystems::sd;

    let mut rc = AllocString::new();
    let _ = write!(rc, "# /etc/rc.conf -- generated by Microvisor\r\n");
    let _ = write!(
        rc,
        "# Do not edit. Configuration is compiled into firmware.\r\n\r\n"
    );
    let _ = write!(rc, "hostname=\"{}\"\r\n", config::HOSTNAME);
    let _ = write!(rc, "sshd_enable=\"YES\"\r\n");
    let _ = write!(rc, "sshd_port=\"{}\"\r\n", config::ssh::PORT);
    let _ = write!(rc, "sntpd_enable=\"YES\"\r\n");
    let _ = write!(rc, "sntpd_server=\"{}\"\r\n", config::NTP_SERVER);
    let _ = write!(rc, "httpd_enable=\"YES\"\r\n");
    let _ = write!(rc, "httpd_port=\"{}\"\r\n", config::http::PORT);
    let _ = write!(rc, "otad_enable=\"YES\"\r\n");
    let _ = write!(rc, "otad_port=\"{}\"\r\n", config::ota::PORT);
    let _ = write!(rc, "wifi_ap_ssid=\"{}\"\r\n", config::wifi::ap::SSID);
    let _ = write!(
        rc,
        "wifi_ap_auth=\"{}\"\r\n",
        config::wifi::ap::AUTH_MODE
    );
    let _ = write!(rc, "timezone=\"{}\"\r\n", config::time::ZONE);
    let _ = sd::write_file_at("/etc", "RC.CONF", rc.as_bytes());
}

fn generate_loader_conf() {
    use crate::filesystems::sd;

    let mut lc = AllocString::new();
    let _ = write!(lc, "# /boot/loader.conf -- generated by Microvisor\r\n");
    let _ = write!(
        lc,
        "# Do not edit. Hardware config is compiled into firmware.\r\n\r\n"
    );
    let _ = write!(lc, "fatfs_load=\"YES\"\r\n");
    let _ = write!(lc, "sd_spi_bus=\"{}\"\r\n", config::sd_card::DEVICE);
    let _ = write!(
        lc,
        "i2c_frequency=\"{}\"\r\n",
        config::I2C_FREQUENCY_KHZ
    );
    let _ = write!(
        lc,
        "sensor_power_gpio=\"{}\"\r\n",
        config::SENSOR_POWER_GPIO
    );
    let heap = esp_alloc::HEAP.used() + esp_alloc::HEAP.free();
    let _ = write!(lc, "heap_size=\"{}\"\r\n", heap);
    let _ = sd::write_file_at("/boot", "LOADER.CO", lc.as_bytes());
}

pub fn display_cwd(cwd: &str) -> AllocString {
    let home = home_dir();
    if cwd == home {
        AllocString::from("~")
    } else if cwd.starts_with(home.as_str()) {
        let mut d = AllocString::from("~");
        d.push_str(&cwd[home.len()..]);
        d
    } else {
        AllocString::from(cwd)
    }
}

fn cwd_glyph(cwd: &str) -> &'static str {
    let home = home_dir();
    if cwd == "/" {
        prompt::ROOT_ICON
    } else if cwd == home || cwd.starts_with(home.as_str()) {
        prompt::HOME_ICON
    } else {
        prompt::FOLDER_ICON
    }
}

/// Renders the two-line p10k-style shell prompt.
pub fn build_prompt(cwd: &str) -> AllocString {
    use crate::time::{get_current_epoch_secs, is_time_synced};

    let mut p = AllocString::new();

    // Format clock time from SNTP
    let time_str = if is_time_synced() {
        let epoch = get_current_epoch_secs();
        let local_epoch =
            (epoch as i64 + crate::config::time::UTC_OFFSET_HOURS * 3600) as u64;
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
        let mut s = AllocString::new();
        let _ = write!(s, "{:02}:{:02}:{:02} {}", hour12, minute, second, ampm);
        s
    } else {
        let uptime = Instant::now().as_secs();
        let mut s = AllocString::new();
        let _ = write!(s, "{}m{}s", uptime / 60, uptime % 60);
        s
    };

    let display = display_cwd(cwd);
    let glyph = cwd_glyph(cwd);

    // Line 1 — left side
    let mut left = AllocString::new();
    let _ = write!(left, "\x1b[2m{}\x1b[0m", prompt::FRAME_TOP_LEFT);
    let _ = write!(
        left,
        "{}{} {} ",
        prompt::OS_BACKGROUND,
        prompt::OS_FOREGROUND,
        prompt::OS_ICON
    );
    let _ = write!(
        left,
        "{}{}{}",
        prompt::DIR_BACKGROUND,
        prompt::OS_BG_AS_FG,
        prompt::LEFT_SEGMENT_SEPARATOR
    );
    let _ = write!(
        left,
        "{}{} {} {} ",
        prompt::DIR_BACKGROUND,
        prompt::DIR_FOREGROUND,
        glyph,
        display
    );
    let _ = write!(
        left,
        "\x1b[0m{}{}\x1b[0m",
        prompt::DIR_BG_AS_FG,
        prompt::LEFT_SEGMENT_SEPARATOR
    );

    // RAM stats for prompt
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

    // Context: user@hostname
    let mut context_str = AllocString::new();
    let _ = write!(context_str, "{}@{}", SSH_USER, config::HOSTNAME);

    // Line 1 — right side: [context] [ram_pct] [ram_size] [arch] [clock]
    let mut right = AllocString::new();

    // Context segment (user@hostname)
    let _ = write!(
        right,
        "{}{}\x1b[0m",
        prompt::CONTEXT_BG_AS_FG,
        prompt::RIGHT_SEGMENT_SEPARATOR
    );
    let _ = write!(
        right,
        "{}{} {} ",
        prompt::CONTEXT_BACKGROUND,
        prompt::CONTEXT_FOREGROUND,
        context_str
    );

    // RAM percent segment
    let _ = write!(
        right,
        "{}{}{} ",
        prompt::RAM_BACKGROUND,
        prompt::RAM_FOREGROUND,
        prompt::RIGHT_SEGMENT_SEPARATOR
    );
    let _ = write!(
        right,
        "{}{} {} {} {} {} {} {} ",
        prompt::RAM_BACKGROUND,
        prompt::RAM_FOREGROUND,
        ram_pct_str,
        prompt::RAM_ICON,
        ram_str,
        prompt::RIGHT_SUBSEGMENT_SEPARATOR,
        prompt::ARCH_LABEL,
        prompt::ARCH_ICON
    );

    // Clock segment
    let _ = write!(
        right,
        "{}{}{}\x1b[0m",
        prompt::ARCH_BACKGROUND,
        prompt::CLOCK_BG_AS_FG,
        prompt::RIGHT_SEGMENT_SEPARATOR
    );
    let _ = write!(
        right,
        "{}{} {} {} \x1b[0m",
        prompt::CLOCK_BACKGROUND,
        prompt::CLOCK_FOREGROUND,
        time_str,
        prompt::CLOCK_ICON
    );
    let _ = write!(right, "\x1b[2m{}\x1b[0m", prompt::FRAME_TOP_RIGHT);

    // Fill line between left and right.
    // Nerd Font glyphs occupy 2 terminal cells each. The exact count
    // depends on which terminal emulator is in use; this estimate is
    // tuned for Kitty / WezTerm. Count 2 for every NF icon/separator.
    let nf_icons_left = 3;  // OS_ICON, glyph, 1 separator
    let nf_icons_right = 6; // 2 separators, RAM_ICON, ARCH_ICON, CLOCK_ICON, subsep
    let left_vis = 2 + 1 + display.len() + nf_icons_left * 2 + 4; // frame + spaces + text + icons
    let right_vis = context_str.len() + 2
        + ram_pct_str.len() + 1 + ram_str.len() + 1 + prompt::ARCH_LABEL.len()
        + time_str.len() + 2
        + nf_icons_right * 2
        + 8; // spaces + frame
    let fill = (terminal_width() as usize)
        .saturating_sub(left_vis + right_vis)
        .max(1);

    let _ = write!(p, "{}", left);
    let _ = write!(p, "\x1b[2m");
    for _ in 0..fill {
        p.push(prompt::FRAME_LINE);
    }
    let _ = write!(p, "\x1b[0m");
    let _ = write!(p, "{}\r\n", right);

    // Line 2
    let _ = write!(p, "\x1b[2m{}\x1b[0m ", prompt::FRAME_BOT_LEFT);

    p
}

/// FreeBSD-style message of the day shown on SSH connect.
pub fn build_motd(remote: &str) -> AllocString {
    use crate::time;
    use esp_hal::efuse;

    let mut out = AllocString::new();

    // Last login line
    let epoch = time::get_current_epoch_secs();
    if epoch > 0 {
        let ts = time::format_iso8601(epoch);
        let _ = write!(out, "Last login: {} from {}\r\n", ts, remote);
    }

    // Version line (like "FreeBSD 15.0-RELEASE (GENERIC) releng/15.0-...")
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

/// Navigate the working directory. Supports `~`, `..`, absolute and relative paths.
pub fn apply_cd(cwd: &mut AllocString, arg: &str) {
    let arg = arg.trim();
    if arg == "~" || arg.is_empty() {
        *cwd = home_dir();
        return;
    }
    if arg.starts_with("~/") {
        *cwd = home_dir();
        let rest = &arg[2..];
        if !rest.is_empty() {
            for part in rest.split('/') {
                match part {
                    "" | "." => {}
                    ".." => {
                        if let Some(pos) = cwd.rfind('/') {
                            if pos == 0 {
                                cwd.truncate(1);
                            } else {
                                cwd.truncate(pos);
                            }
                        }
                    }
                    name => {
                        if cwd != "/" {
                            cwd.push('/');
                        }
                        cwd.push_str(name);
                    }
                }
            }
        }
        return;
    }

    if arg == "/" {
        cwd.clear();
        cwd.push('/');
        return;
    }

    if arg.starts_with('/') {
        cwd.clear();
        cwd.push('/');
    }

    for part in arg.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                if let Some(pos) = cwd.rfind('/') {
                    if pos == 0 {
                        cwd.truncate(1);
                    } else {
                        cwd.truncate(pos);
                    }
                }
            }
            name => {
                if cwd != "/" {
                    cwd.push('/');
                }
                cwd.push_str(name);
            }
        }
    }
}

/// Resolve a filename relative to CWD into a full path for SD operations.
pub fn resolve_path(cwd: &str, name: &str) -> AllocString {
    if name.starts_with('/') {
        AllocString::from(name)
    } else {
        let mut path = AllocString::from(cwd);
        if !path.ends_with('/') {
            path.push('/');
        }
        path.push_str(name);
        path
    }
}

/// Dispatch a shell command. Returns `(output, should_exit)`.
pub fn dispatch(cmd: &str, cwd: &mut AllocString) -> (AllocString, bool) {
    let cmd = cmd.trim();

    if cmd == "exit" || cmd == "quit" {
        let mut out = AllocString::new();
        let _ = write!(out, "\x1b[33mgoodbye!\x1b[0m\r\n");
        return (out, true);
    }

    if cmd.starts_with("cd ") {
        let previous = cwd.clone();
        apply_cd(cwd, &cmd[3..]);
        if !crate::filesystems::sd::directory_exists(cwd.as_str()) {
            *cwd = previous;
            return (coreutils::fmt_error(&"no such directory"), false);
        }
        return (AllocString::new(), false);
    }
    if cmd == "cd" {
        *cwd = home_dir();
        return (AllocString::new(), false);
    }

    // Split command and args
    let (name, args) = match cmd.find(' ') {
        Some(pos) => (&cmd[..pos], cmd[pos + 1..].trim()),
        None => (cmd, ""),
    };

    let out = match name {
        "help" | "h" => coreutils::help::run(),
        "ls" => {
            if args.is_empty() {
                coreutils::ls::run(cwd)
            } else {
                let mut target = cwd.clone();
                apply_cd(&mut target, args);
                coreutils::ls::run(&target)
            }
        }
        "pwd" => {
            let mut o = AllocString::new();
            let _ = write!(o, "{}\r\n", cwd);
            o
        }
        "mkdir" => coreutils::mkdir::run(cwd, args),
        "cp" => coreutils::cp::run(args),
        "mv" => coreutils::mv::run(args),
        "rm" => coreutils::rm::run(cwd, args),
        "cat" => coreutils::cat::run(cwd, args),
        "touch" => coreutils::touch::run(cwd, args),
        "uptime" => coreutils::uptime::run(),
        "free" => coreutils::free::run(),
        "date" => coreutils::date::run(),
        "df" => coreutils::df::run(),
        "whoami" => coreutils::whoami::run(),
        "hostname" => coreutils::hostname::run(),
        "ifconfig" => coreutils::ifconfig::run(),
        "sensors" => coreutils::sensors::run(),
        "microfetch" | "fetch" => crate::programs::microfetch::run(),
        "microtop" | "top" => {
            let w = terminal_width() as u16;
            crate::programs::microtop::render_frame(w, 24)
        }
        "reboot" => {
            esp_hal::system::software_reset();
        }
        "clear" => {
            let mut o = AllocString::new();
            let _ = write!(o, "\x1b[2J\x1b[H");
            o
        }
        "" => AllocString::new(),
        unknown => {
            let mut o = AllocString::new();
            let _ = write!(o, "\x1b[31mcommand not found: {}\x1b[0m\r\n", unknown);
            o
        }
    };

    (out, false)
}

// ─── SSH host key management ────────────────────────────────────────────────────

/// Load SSH host key from SD card, or generate a new one if missing.
fn load_or_generate_host_key() -> [u8; 32] {
    let home = home_dir();
    let ssh_dir = resolve_path(home.as_str(), ".ssh");

    // Try loading from SD card
    if let Ok(contents) = crate::filesystems::sd::read_file_at::<32>(ssh_dir.as_str(), "HOST_KEY") {
        if contents.len() == 32 {
            let mut key = [0u8; 32];
            key.copy_from_slice(contents.as_slice());
            return key;
        }
    }

    // Generate a new key using hardware RNG
    let rng = esp_hal::rng::Rng::new();
    let mut key = [0u8; 32];
    for chunk in key.chunks_mut(4) {
        let random = rng.random();
        let bytes = random.to_le_bytes();
        chunk.copy_from_slice(&bytes[..chunk.len()]);
    }

    // Save to SD card for persistence across reboots
    let _ = crate::filesystems::sd::write_file_at(ssh_dir.as_str(), "HOST_KEY", &key);

    defmt::info!("generated new SSH host key");
    key
}

// ─── Shell history persistence ──────────────────────────────────────────────────

const HISTORY_FILE: &str = ".MSH_HIST";

fn load_history(history: &mut crate::services::ssh::history::History<256>) {
    let home = home_dir();
    if let Ok(contents) = crate::filesystems::sd::read_file_at::<4096>(home.as_str(), HISTORY_FILE)
    {
        if let Ok(text) = core::str::from_utf8(contents.as_slice()) {
            for line in text.lines() {
                let line = line.trim();
                if !line.is_empty() {
                    let _ = history.add(line);
                }
            }
        }
    }
}

fn save_history(history: &crate::services::ssh::history::History<256>) {
    let home = home_dir();
    let mut buf = AllocString::new();
    for entry in history.iter() {
        buf.push_str(entry);
        buf.push('\n');
    }
    let path = resolve_path(home.as_str(), HISTORY_FILE);
    let _ = crate::filesystems::sd::write_file_chunk(path.as_str(), 0, buf.as_bytes());
}

// ─── SSH Server Task ───────────────────────────────────────────────────────────

#[derive(Clone, Copy)]
pub struct TermSize {
    pub width: u32,
    pub height: u32,
}

struct SshBehavior<'a> {
    socket: TcpSocket<'a>,
    rng: CryptoRng,
    host_key: SecretKey,
    term_size: &'a core::cell::Cell<TermSize>,
}

impl<'a> Behavior for SshBehavior<'a> {
    type Stream = TcpSocket<'a>;
    fn stream(&mut self) -> &mut Self::Stream {
        &mut self.socket
    }

    type Random = CryptoRng;
    fn random(&mut self) -> &mut Self::Random {
        &mut self.rng
    }

    fn host_secret_key(&self) -> &SecretKey {
        &self.host_key
    }

    type User = ();
    fn allow_user(&mut self, username: &str, auth_method: &AuthMethod) -> Option<()> {
        if username == SSH_USER && matches!(auth_method, AuthMethod::None) {
            Some(())
        } else {
            None
        }
    }

    fn allow_shell(&self) -> bool {
        true
    }

    fn on_pty_request(&mut self, width: u32, height: u32) {
        self.term_size.set(TermSize { width, height });
    }

    type Command = ();
    fn parse_command(&mut self, _: &str) {}
}

/// Redraw only the input line (line 2 of prompt), preserving line 1.
async fn redraw_line<T: Behavior>(
    channel: &mut crate::services::ssh::Channel<'_, '_, T>,
    terminal: &crate::services::ssh::terminal::Terminal<256>,
    _cwd: &str,
) {
    let _ = channel.write_all_stdout(b"\r\x1b[K").await;
    let mut prefix = AllocString::new();
    let _ = write!(
        prefix,
        "{}{}{} ",
        prompt::FRAME_COLOR,
        prompt::FRAME_BOT_LEFT,
        prompt::RESET
    );
    let _ = channel.write_all_stdout(prefix.as_bytes()).await;

    if let Ok(buf) = terminal.buffer_str() {
        let _ = channel.write_all_stdout(buf.as_bytes()).await;
        let cursor = terminal.cursor_position();
        let buf_len = buf.len();
        if cursor < buf_len {
            let mut back = AllocString::new();
            let _ = write!(back, "\x1b[{}D", buf_len - cursor);
            let _ = channel.write_all_stdout(back.as_bytes()).await;
        }
    }
}

#[embassy_executor::task]
pub async fn task(stack: Stack<'static>) {
    info!("Microshell (SSH) listening on port {}", SSH_PORT);

    loop {
        static mut RX_BUFFER: [u8; RX_BUF_SIZE] = [0; RX_BUF_SIZE];
        static mut TX_BUFFER: [u8; TX_BUF_SIZE] = [0; TX_BUF_SIZE];

        let socket = unsafe {
            TcpSocket::new(
                stack,
                &mut *core::ptr::addr_of_mut!(RX_BUFFER),
                &mut *core::ptr::addr_of_mut!(TX_BUFFER),
            )
        };

        let term_size = core::cell::Cell::new(TermSize {
            width: 80,
            height: 24,
        });

        let mut behavior = SshBehavior {
            socket,
            rng: CryptoRng(Rng::new()),
            host_key: SecretKey::Ed25519 {
                secret_key: SigningKey::from_bytes(&load_or_generate_host_key()),
            },
            term_size: &term_size,
        };

        if let Err(e) = behavior.socket.accept(SSH_PORT).await {
            info!("SSH accept failed: {:?}", e);
            embassy_time::Timer::after(Duration::from_millis(250)).await;
            continue;
        }

        let remote_str = behavior
            .socket
            .remote_endpoint()
            .map(|ep| {
                let mut s = AllocString::new();
                let _ = write!(s, "{}", ep);
                s
            })
            .unwrap_or_else(|| AllocString::from("unknown"));
        info!("SSH client connected from {}", remote_str.as_str());
        behavior.socket.set_timeout(Some(Duration::from_secs(300)));

        let mut packet_buffer = [0u8; 4096];
        let mut transport = Transport::new(&mut packet_buffer, behavior);

        match transport.accept().await {
            Ok(mut channel) => {
                info!("SSH channel opened");

                match channel.request() {
                    Request::Shell => {
                        let ts = term_size.get();
                        info!("Terminal size: {}x{}", ts.width, ts.height);
                        set_terminal_width(ts.width);

                        let _ = channel.write_all_stdout(b"\x1b[2J\x1b[H").await;

                        let motd = build_motd(remote_str.as_str());
                        let _ = channel.write_all_stdout(motd.as_bytes()).await;

                        let mut cwd = home_dir();

                        // Execute ~/.mshrc commands
                        if let Ok(mshrc) =
                            crate::filesystems::sd::read_file_at::<1024>(cwd.as_str(), ".MSHRC")
                        {
                            if let Ok(text) = core::str::from_utf8(mshrc.as_slice()) {
                                for line in text.lines() {
                                    let line = line.trim();
                                    if line.is_empty() || line.starts_with('#') {
                                        continue;
                                    }
                                    let (output, _) = dispatch(line, &mut cwd);
                                    if !output.is_empty() {
                                        let _ = channel.write_all_stdout(output.as_bytes()).await;
                                    }
                                }
                            }
                        }

                        let prompt_str = build_prompt(&cwd);
                        let _ = channel.write_all_stdout(prompt_str.as_bytes()).await;

                        use crate::services::ssh::history::{History, HistoryConfig};
                        use crate::services::ssh::terminal::{
                            Terminal, TerminalConfig, TerminalEvent,
                        };

                        let mut terminal = Terminal::<256>::new(TerminalConfig {
                            buffer_size: 256,
                            prompt: "",
                            echo: true,
                            ansi_enabled: true,
                        });

                        let mut history = History::<256>::new(HistoryConfig {
                            max_entries: 16,
                            deduplicate: true,
                        });
                        load_history(&mut history);

                        loop {
                            let mut byte_buf = [0u8; 1];
                            match channel.read_exact_stdin(&mut byte_buf).await {
                                Ok(0) => break,
                                Err(_) => break,
                                Ok(_) => {}
                            }

                            let byte = byte_buf[0];

                            if byte == CTRL_L {
                                let _ = channel.write_all_stdout(b"\x1b[2J\x1b[H").await;
                                terminal.clear_buffer();
                                let p = build_prompt(&cwd);
                                let _ = channel.write_all_stdout(p.as_bytes()).await;
                                continue;
                            }

                            let byte = match byte {
                                CTRL_P => {
                                    if let Some(entry) = history.previous() {
                                        let _ = terminal.set_buffer(entry);
                                        redraw_line(&mut channel, &terminal, &cwd).await;
                                    }
                                    continue;
                                }
                                CTRL_N => {
                                    if let Some(entry) = history.next() {
                                        let _ = terminal.set_buffer(entry);
                                    } else {
                                        terminal.clear_buffer();
                                    }
                                    redraw_line(&mut channel, &terminal, &cwd).await;
                                    continue;
                                }
                                CTRL_W => {
                                    let buf_copy =
                                        AllocString::from(terminal.buffer_str().unwrap_or(""));
                                    let trimmed = buf_copy.trim_end();
                                    if let Some(last_space) = trimmed.rfind(' ') {
                                        let _ = terminal.set_buffer(&buf_copy[..last_space + 1]);
                                    } else {
                                        terminal.clear_buffer();
                                    }
                                    redraw_line(&mut channel, &terminal, &cwd).await;
                                    continue;
                                }
                                CTRL_U => {
                                    terminal.clear_buffer();
                                    redraw_line(&mut channel, &terminal, &cwd).await;
                                    continue;
                                }
                                other => other,
                            };

                            let key = match terminal.process_byte(byte) {
                                Some(k) => k,
                                None => continue,
                            };

                            let event = terminal.handle_key(key);

                            match event {
                                TerminalEvent::CommandReady => {
                                    let _ = channel.write_all_stdout(b"\r\n").await;
                                    if let Ok(cmd) = terminal.take_command() {
                                        let cmd_str = cmd.as_str().trim();
                                        if !cmd_str.is_empty() {
                                            let _ = history.add(cmd_str);
                                        }
                                        let (output, should_exit) = dispatch(cmd_str, &mut cwd);
                                        if !output.is_empty() {
                                            let _ =
                                                channel.write_all_stdout(output.as_bytes()).await;
                                        }
                                        if should_exit {
                                            break;
                                        }
                                    }
                                    history.reset_position();
                                    let p = build_prompt(&cwd);
                                    let _ = channel.write_all_stdout(p.as_bytes()).await;
                                }
                                TerminalEvent::EmptyCommand => {
                                    let _ = channel.write_all_stdout(b"\r\n").await;
                                    let p = build_prompt(&cwd);
                                    let _ = channel.write_all_stdout(p.as_bytes()).await;
                                }
                                TerminalEvent::BufferChanged | TerminalEvent::CursorMoved => {
                                    redraw_line(&mut channel, &terminal, &cwd).await;
                                }
                                TerminalEvent::Interrupt => {
                                    terminal.clear_buffer();
                                    let _ = channel.write_all_stdout(b"^C\r\n").await;
                                    history.reset_position();
                                    let p = build_prompt(&cwd);
                                    let _ = channel.write_all_stdout(p.as_bytes()).await;
                                }
                                TerminalEvent::EndOfFile => break,
                                TerminalEvent::HistoryPrevious => {
                                    if let Some(entry) = history.previous() {
                                        let _ = terminal.set_buffer(entry);
                                        redraw_line(&mut channel, &terminal, &cwd).await;
                                    }
                                }
                                TerminalEvent::HistoryNext => {
                                    if let Some(entry) = history.next() {
                                        let _ = terminal.set_buffer(entry);
                                    } else {
                                        terminal.clear_buffer();
                                    }
                                    redraw_line(&mut channel, &terminal, &cwd).await;
                                }
                                _ => {}
                            }
                        }

                        save_history(&history);
                        let _ = channel.exit(0).await;
                    }
                    _ => {
                        let _ = channel
                            .write_all_stderr(b"Only shell mode is supported.\n")
                            .await;
                        let _ = channel.exit(1).await;
                    }
                }
            }
            Err(_) => {
                info!("SSH handshake failed");
            }
        }

        info!("SSH client disconnected");
    }
}
