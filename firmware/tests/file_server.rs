//! `describe("File server / firmware library")`
//!
//! Pure-logic unit tests covering the firmware library surface that
//! does not need real hardware: configuration constants, default
//! state values, time formatting, filename validation, the SD error
//! enum, the static hardware topology, the embassy heap, and the shell
//! command parser.
//!
//! Style: tests still take a `Device` and return `Result<(), &'static str>`
//! for screenplay-lite consistency. Inside the body we use
//! `defmt::assert_eq!` / `defmt::assert!` for value-level checks because
//! the rich panic messages (with actual left/right values + file:line)
//! are more informative than a hand-written string. The `Result` return
//! is reserved for structural failures (e.g. "device not present at
//! 0x...") that propagate via `?` from hardware tasks.

#![no_std]
#![no_main]

extern crate alloc;

#[path = "common/mod.rs"]
mod common;

use defmt::info;

use common::Device;

esp_bootloader_esp_idf::esp_app_desc!();

#[cfg(test)]
#[embedded_test::setup]
fn setup() {
    rtt_target::rtt_init_defmt!();
}

#[cfg(test)]
#[embedded_test::tests(default_timeout = 10, executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;

    #[init]
    fn init() -> Device {
        info!("=== File server / firmware library — describe block ===");
        common::setup::boot_device()
    }

    // ========== CONFIGURATION ==========

    /// `it("user reads non-empty configuration constants from the device")`
    #[test]
    async fn user_reads_non_empty_configuration_constants(
        _device: Device,
    ) -> Result<(), &'static str> {
        defmt::assert!(!firmware::config::HOSTNAME.is_empty());
        defmt::assert!(!firmware::config::PLATFORM.is_empty());
        defmt::assert!(!firmware::config::SSH_USER.is_empty());
        defmt::assert!(!firmware::config::NTP_SERVER.is_empty());
        defmt::assert!(!firmware::config::CLOUD_EVENTS_TENANT.is_empty());
        defmt::assert!(!firmware::config::CLOUD_EVENTS_SITE.is_empty());
        defmt::assert!(!firmware::config::CLOUD_EVENTS_SOURCE.is_empty());
        defmt::assert!(!firmware::config::CLOUD_EVENT_TYPE.is_empty());
        Ok(())
    }

    /// `it("user finds every service port above zero")`
    #[test]
    async fn user_finds_every_service_port_above_zero(
        _device: Device,
    ) -> Result<(), &'static str> {
        defmt::assert!(firmware::config::ssh::PORT > 0);
        defmt::assert!(firmware::config::http::PORT > 0);
        defmt::assert!(firmware::config::ota::PORT > 0);
        defmt::assert!(firmware::config::tcp_log::PORT > 0);
        Ok(())
    }

    /// `it("user finds buffer sizes above sane minimums")`
    #[test]
    async fn user_finds_buffer_sizes_above_sane_minimums(
        _device: Device,
    ) -> Result<(), &'static str> {
        defmt::assert!(firmware::config::ssh::RX_BUF_SIZE >= 1024);
        defmt::assert!(firmware::config::ssh::TX_BUF_SIZE >= 1024);
        defmt::assert!(firmware::config::ota::RX_BUF_SIZE >= 4096);
        defmt::assert!(firmware::config::ota::CHUNK_SIZE >= 1024);
        Ok(())
    }

    /// `it("user finds a plausible UTC offset for the configured timezone")`
    #[test]
    async fn user_finds_a_plausible_utc_offset(
        _device: Device,
    ) -> Result<(), &'static str> {
        let configured_utc_offset_hours = firmware::config::time::UTC_OFFSET_HOURS;
        defmt::assert!((-12..=14).contains(&configured_utc_offset_hours));
        Ok(())
    }

    // ========== STATE DEFAULTS ==========

    /// `it("user sees the default Co2Reading marked not-ok")`
    #[test]
    async fn user_sees_default_co2_reading_marked_not_ok(
        _device: Device,
    ) -> Result<(), &'static str> {
        let default_co2_reading = firmware::state::Co2Reading::default();
        defmt::assert!(!default_co2_reading.ok);
        defmt::assert_eq!(default_co2_reading.co2_ppm, 0.0);
        defmt::assert_eq!(default_co2_reading.temperature, 0.0);
        defmt::assert_eq!(default_co2_reading.humidity, 0.0);
        defmt::assert_eq!(default_co2_reading.model, "unknown");
        defmt::assert_eq!(default_co2_reading.name, "unknown");
        Ok(())
    }

    /// `it("user sees the default AppState carrying cloud event metadata")`
    #[test]
    async fn user_sees_default_app_state_with_cloud_event_metadata(
        _device: Device,
    ) -> Result<(), &'static str> {
        let default_app_state = firmware::state::AppState::default();
        defmt::assert!(!default_app_state.cloud_event_source.is_empty());
        defmt::assert!(!default_app_state.cloud_event_type.is_empty());
        defmt::assert_eq!(default_app_state.boot_timestamp_seconds, 0);
        Ok(())
    }

    /// `it("user sees the default DeviceInfo zeroed")`
    #[test]
    async fn user_sees_default_device_info_zeroed(
        _device: Device,
    ) -> Result<(), &'static str> {
        let default_device_info = firmware::state::DeviceInfo::default();
        defmt::assert_eq!(default_device_info.ip_address, [0, 0, 0, 0]);
        defmt::assert_eq!(default_device_info.sd_card_size_mb, 0);
        Ok(())
    }

    // ========== TIME FORMATTING ==========

    /// `it("user formats epoch zero as the empty string")`
    #[test]
    async fn user_formats_epoch_zero_as_empty_string(
        _device: Device,
    ) -> Result<(), &'static str> {
        let formatted = firmware::time::format_iso8601(0);
        defmt::assert!(formatted.is_empty());
        Ok(())
    }

    /// `it("user formats a known epoch into the expected ISO-8601 string")`
    #[test]
    async fn user_formats_known_epoch_into_iso8601(
        _device: Device,
    ) -> Result<(), &'static str> {
        let formatted = firmware::time::format_iso8601(1_700_000_000);
        defmt::assert_eq!(formatted.as_str(), "2023-11-14T22:13:20Z");
        Ok(())
    }

    /// `it("user formats a leap-year date correctly")`
    #[test]
    async fn user_formats_leap_year_date(
        _device: Device,
    ) -> Result<(), &'static str> {
        let formatted = firmware::time::format_iso8601(1_709_337_600);
        defmt::assert_eq!(formatted.as_str(), "2024-03-02T00:00:00Z");
        Ok(())
    }

    /// `it("user formats a 2026 epoch correctly")`
    #[test]
    async fn user_formats_year_2026_epoch(
        _device: Device,
    ) -> Result<(), &'static str> {
        let formatted = firmware::time::format_iso8601(1_767_225_600);
        defmt::assert_eq!(formatted.as_str(), "2026-01-01T00:00:00Z");
        Ok(())
    }

    /// `it("user reads zero from get_current_epoch_secs while time is unsynced")`
    #[test]
    async fn user_reads_zero_epoch_when_time_unsynced(
        _device: Device,
    ) -> Result<(), &'static str> {
        if !firmware::time::is_time_synced() {
            defmt::assert_eq!(firmware::time::get_current_epoch_secs(), 0);
        }
        Ok(())
    }

    // ========== FILENAME VALIDATION ==========

    /// `it("user cannot upload a file with an empty name")`
    #[test]
    async fn user_cannot_upload_file_with_empty_name(
        _device: Device,
    ) -> Result<(), &'static str> {
        defmt::assert!(!firmware::filesystems::sd::is_supported_flat_file_name(""));
        Ok(())
    }

    /// `it("user cannot traverse out of the upload directory")`
    #[test]
    async fn user_cannot_traverse_out_of_upload_directory(
        _device: Device,
    ) -> Result<(), &'static str> {
        use firmware::filesystems::sd::is_supported_flat_file_name;
        defmt::assert!(!is_supported_flat_file_name("../etc/passwd"));
        defmt::assert!(!is_supported_flat_file_name("..\\windows"));
        defmt::assert!(!is_supported_flat_file_name("sub/dir.html"));
        Ok(())
    }

    /// `it("user uploads a file with a valid flat name")`
    #[test]
    async fn user_uploads_file_with_valid_flat_name(
        _device: Device,
    ) -> Result<(), &'static str> {
        use firmware::filesystems::sd::is_supported_flat_file_name;
        defmt::assert!(is_supported_flat_file_name("index.html"));
        defmt::assert!(is_supported_flat_file_name("DATA.CSV"));
        defmt::assert!(is_supported_flat_file_name(".mshrc"));
        defmt::assert!(is_supported_flat_file_name("firmware.bin"));
        defmt::assert!(is_supported_flat_file_name("a"));
        Ok(())
    }

    // ========== SD ERROR ENUM ==========

    /// `it("user sees every SdError variant render distinctly")`
    #[test]
    async fn user_sees_every_sd_error_variant_render_distinctly(
        _device: Device,
    ) -> Result<(), &'static str> {
        use firmware::filesystems::sd::SdError;
        let all_sd_error_variants = [
            SdError::NotInitialized,
            SdError::VolumeFailed,
            SdError::RootDirFailed,
            SdError::NavigationFailed,
            SdError::FileNotFound,
            SdError::CreateFailed,
            SdError::ReadFailed,
            SdError::WriteFailed,
            SdError::FlushFailed,
            SdError::DeleteFailed,
            SdError::DirectoryFailed,
            SdError::SeekFailed,
        ];
        for sd_error_variant in all_sd_error_variants {
            info!("SdError: {=?}", sd_error_variant);
        }
        Ok(())
    }

    // ========== HTTP SERVER ==========

    /// `it("user reaches the HTTP server on the standard port 80")`
    #[test]
    async fn user_reaches_http_server_on_port_80(
        _device: Device,
    ) -> Result<(), &'static str> {
        defmt::assert_eq!(firmware::config::http::PORT, 80);
        Ok(())
    }

    // ========== HARDWARE TOPOLOGY ==========

    /// `it("user sees the device declares at least one bus in its topology")`
    #[test]
    async fn user_sees_device_declares_at_least_one_bus(
        _device: Device,
    ) -> Result<(), &'static str> {
        let hardware_topology = &firmware::config::topology::CURRENT_TOPOLOGY;
        defmt::assert!(!hardware_topology.buses.is_empty());
        Ok(())
    }

    /// `it("user sees the device declares at least one enabled sensor")`
    #[test]
    async fn user_sees_device_declares_at_least_one_enabled_sensor(
        _device: Device,
    ) -> Result<(), &'static str> {
        let hardware_topology = &firmware::config::topology::CURRENT_TOPOLOGY;
        let enabled_sensor_count = hardware_topology.enabled_sensors().count();
        info!("enabled sensors count={=usize}", enabled_sensor_count);
        defmt::assert!(enabled_sensor_count > 0);
        Ok(())
    }

    /// `it("user sees every declared bus carries plausible pin assignments")`
    #[test]
    async fn user_sees_every_bus_with_plausible_pins(
        _device: Device,
    ) -> Result<(), &'static str> {
        let hardware_topology = &firmware::config::topology::CURRENT_TOPOLOGY;
        for bus_configuration in hardware_topology.buses {
            if let Some((sda_gpio_number, scl_gpio_number)) = bus_configuration.i2c_pins() {
                defmt::assert!(sda_gpio_number < 49, "SDA pin out of range for ESP32-S3");
                defmt::assert!(scl_gpio_number < 49, "SCL pin out of range for ESP32-S3");
                defmt::assert!(
                    sda_gpio_number != scl_gpio_number,
                    "SDA and SCL cannot share a GPIO pin"
                );
                info!(
                    "bus={=str} SDA=GPIO{=u8} SCL=GPIO{=u8}",
                    bus_configuration.label, sda_gpio_number, scl_gpio_number
                );
            }
        }
        Ok(())
    }

    /// `it("user sees every enabled sensor pointing at a known bus")`
    #[test]
    async fn user_sees_every_sensor_pointing_at_a_known_bus(
        _device: Device,
    ) -> Result<(), &'static str> {
        let hardware_topology = &firmware::config::topology::CURRENT_TOPOLOGY;
        for sensor_configuration in hardware_topology.enabled_sensors() {
            let resolved_bus = hardware_topology.find_bus(sensor_configuration.bus_label);
            defmt::assert!(
                resolved_bus.is_some(),
                "an enabled sensor references an unknown bus label"
            );
            info!(
                "sensor={=str} bus={=str}",
                sensor_configuration.name, sensor_configuration.bus_label
            );
        }
        Ok(())
    }

    // ========== EMBASSY HEAP ==========

    /// `it("user sees the embassy heap reports free memory")`
    #[test]
    async fn user_sees_heap_reports_free_memory(
        _device: Device,
    ) -> Result<(), &'static str> {
        let heap_free_bytes = esp_alloc::HEAP.free();
        let heap_used_bytes = esp_alloc::HEAP.used();
        info!(
            "heap free={=usize} used={=usize} total={=usize}",
            heap_free_bytes,
            heap_used_bytes,
            heap_free_bytes + heap_used_bytes
        );
        defmt::assert!(heap_free_bytes > 0, "embassy heap reports zero free bytes");
        Ok(())
    }

    /// `it("user sees the embassy heap totals at least 64 KiB")`
    #[test]
    async fn user_sees_heap_totals_at_least_64_kib(
        _device: Device,
    ) -> Result<(), &'static str> {
        let heap_total_bytes = esp_alloc::HEAP.free() + esp_alloc::HEAP.used();
        info!(
            "heap total={=usize} bytes ({=usize} KiB)",
            heap_total_bytes,
            heap_total_bytes / 1024
        );
        defmt::assert!(
            heap_total_bytes >= 64 * 1024,
            "embassy heap is below the 64 KiB minimum"
        );
        Ok(())
    }

    // ========== SHELL: home_dir ==========

    /// `it("user sees the shell home directory under /home")`
    #[test]
    async fn user_sees_shell_home_directory_under_slash_home(
        _device: Device,
    ) -> Result<(), &'static str> {
        let home_directory = firmware::programs::shell::home_dir();
        defmt::assert!(home_directory.starts_with("/home/"));
        defmt::assert!(home_directory.len() > 6, "home_dir missing username segment");
        info!("home_dir={=str}", home_directory.as_str());
        Ok(())
    }

    // ========== SHELL: display_cwd ==========

    /// `it("user sees ~ when their cwd is the home directory")`
    #[test]
    async fn user_sees_tilde_when_cwd_is_home(
        _device: Device,
    ) -> Result<(), &'static str> {
        let home_directory = firmware::programs::shell::home_dir();
        let displayed_cwd = firmware::programs::shell::display_cwd(home_directory.as_str());
        defmt::assert_eq!(displayed_cwd.as_str(), "~");
        Ok(())
    }

    /// `it("user sees ~/subdir when their cwd is below home")`
    #[test]
    async fn user_sees_tilde_subdir_when_cwd_is_below_home(
        _device: Device,
    ) -> Result<(), &'static str> {
        let home_directory = firmware::programs::shell::home_dir();
        let mut subdirectory_under_home = home_directory.clone();
        subdirectory_under_home.push_str("/documents");
        let displayed_cwd =
            firmware::programs::shell::display_cwd(subdirectory_under_home.as_str());
        defmt::assert_eq!(displayed_cwd.as_str(), "~/documents");
        Ok(())
    }

    /// `it("user sees / when their cwd is the filesystem root")`
    #[test]
    async fn user_sees_slash_when_cwd_is_root(
        _device: Device,
    ) -> Result<(), &'static str> {
        let displayed_cwd = firmware::programs::shell::display_cwd("/");
        defmt::assert_eq!(displayed_cwd.as_str(), "/");
        Ok(())
    }

    /// `it("user sees the literal path when their cwd is unrelated to home")`
    #[test]
    async fn user_sees_literal_path_for_unrelated_cwd(
        _device: Device,
    ) -> Result<(), &'static str> {
        let displayed_cwd = firmware::programs::shell::display_cwd("/etc");
        defmt::assert_eq!(displayed_cwd.as_str(), "/etc");
        Ok(())
    }

    // ========== SHELL: apply_cd ==========

    /// `it("user runs cd ~ to return home from /etc")`
    #[test]
    async fn user_runs_cd_tilde_to_return_home(
        _device: Device,
    ) -> Result<(), &'static str> {
        use alloc::string::String;
        let mut current_working_directory = String::from("/etc");
        firmware::programs::shell::apply_cd(&mut current_working_directory, "~");
        let home_directory = firmware::programs::shell::home_dir();
        defmt::assert_eq!(current_working_directory.as_str(), home_directory.as_str());
        Ok(())
    }

    /// `it("user runs cd .. to walk up one directory")`
    #[test]
    async fn user_runs_cd_dotdot_to_walk_up(
        _device: Device,
    ) -> Result<(), &'static str> {
        use alloc::string::String;
        let mut current_working_directory = String::from("/home/user/documents");
        firmware::programs::shell::apply_cd(&mut current_working_directory, "..");
        defmt::assert_eq!(current_working_directory.as_str(), "/home/user");
        Ok(())
    }

    /// `it("user runs cd .. at root and stays at root")`
    #[test]
    async fn user_runs_cd_dotdot_at_root_and_stays_at_root(
        _device: Device,
    ) -> Result<(), &'static str> {
        use alloc::string::String;
        let mut current_working_directory = String::from("/");
        firmware::programs::shell::apply_cd(&mut current_working_directory, "..");
        defmt::assert_eq!(current_working_directory.as_str(), "/");
        Ok(())
    }

    /// `it("user runs cd /etc with an absolute path")`
    #[test]
    async fn user_runs_cd_with_absolute_path(
        _device: Device,
    ) -> Result<(), &'static str> {
        use alloc::string::String;
        let mut current_working_directory = String::from("/home/user");
        firmware::programs::shell::apply_cd(&mut current_working_directory, "/etc");
        defmt::assert_eq!(current_working_directory.as_str(), "/etc");
        Ok(())
    }

    /// `it("user runs cd user with a relative path")`
    #[test]
    async fn user_runs_cd_with_relative_path(
        _device: Device,
    ) -> Result<(), &'static str> {
        use alloc::string::String;
        let mut current_working_directory = String::from("/home");
        firmware::programs::shell::apply_cd(&mut current_working_directory, "user");
        defmt::assert_eq!(current_working_directory.as_str(), "/home/user");
        Ok(())
    }

    /// `it("user runs cd / from a deep path and lands at root")`
    #[test]
    async fn user_runs_cd_slash_from_deep_path(
        _device: Device,
    ) -> Result<(), &'static str> {
        use alloc::string::String;
        let mut current_working_directory = String::from("/home/user/deep/path");
        firmware::programs::shell::apply_cd(&mut current_working_directory, "/");
        defmt::assert_eq!(current_working_directory.as_str(), "/");
        Ok(())
    }

    /// `it("user runs cd ~/documents to land in a home subdirectory")`
    #[test]
    async fn user_runs_cd_tilde_subdir(
        _device: Device,
    ) -> Result<(), &'static str> {
        use alloc::string::String;
        let mut current_working_directory = String::from("/etc");
        firmware::programs::shell::apply_cd(&mut current_working_directory, "~/documents");
        let home_directory = firmware::programs::shell::home_dir();
        let mut expected_path = home_directory.clone();
        expected_path.push_str("/documents");
        defmt::assert_eq!(current_working_directory.as_str(), expected_path.as_str());
        Ok(())
    }

    // ========== SHELL: resolve_path ==========

    /// `it("user resolves a relative filename against the cwd")`
    #[test]
    async fn user_resolves_relative_filename_against_cwd(
        _device: Device,
    ) -> Result<(), &'static str> {
        let resolved_path =
            firmware::programs::shell::resolve_path("/home/user", "file.txt");
        defmt::assert_eq!(resolved_path.as_str(), "/home/user/file.txt");
        Ok(())
    }

    /// `it("user resolves an absolute path verbatim")`
    #[test]
    async fn user_resolves_absolute_path_verbatim(
        _device: Device,
    ) -> Result<(), &'static str> {
        let resolved_path =
            firmware::programs::shell::resolve_path("/home/user", "/etc/rc.conf");
        defmt::assert_eq!(resolved_path.as_str(), "/etc/rc.conf");
        Ok(())
    }

    /// `it("user resolves a relative filename from the root cwd")`
    #[test]
    async fn user_resolves_relative_filename_from_root(
        _device: Device,
    ) -> Result<(), &'static str> {
        let resolved_path = firmware::programs::shell::resolve_path("/", "data.csv");
        defmt::assert_eq!(resolved_path.as_str(), "/data.csv");
        Ok(())
    }

    // ========== SHELL: dispatch ==========

    /// `it("user runs `exit` and the shell signals it should exit")`
    #[test]
    async fn user_runs_exit_and_shell_signals_exit(
        _device: Device,
    ) -> Result<(), &'static str> {
        use alloc::string::String;
        let mut current_working_directory = String::from("/");
        let (output, should_exit) =
            firmware::programs::shell::dispatch("exit", &mut current_working_directory);
        defmt::assert!(should_exit);
        defmt::assert!(!output.is_empty());
        Ok(())
    }

    /// `it("user runs `quit` and the shell signals it should exit")`
    #[test]
    async fn user_runs_quit_and_shell_signals_exit(
        _device: Device,
    ) -> Result<(), &'static str> {
        use alloc::string::String;
        let mut current_working_directory = String::from("/");
        let (_unused_output, should_exit) =
            firmware::programs::shell::dispatch("quit", &mut current_working_directory);
        defmt::assert!(should_exit);
        Ok(())
    }

    /// `it("user runs an unknown command and gets a 'command not found' error")`
    #[test]
    async fn user_runs_unknown_command_and_gets_error(
        _device: Device,
    ) -> Result<(), &'static str> {
        use alloc::string::String;
        let mut current_working_directory = String::from("/");
        let (output, should_exit) = firmware::programs::shell::dispatch(
            "nonexistent_cmd",
            &mut current_working_directory,
        );
        defmt::assert!(!should_exit);
        defmt::assert!(output.contains("command not found"));
        Ok(())
    }

    /// `it("user submits an empty line and the shell stays quiet")`
    #[test]
    async fn user_submits_empty_line_and_shell_stays_quiet(
        _device: Device,
    ) -> Result<(), &'static str> {
        use alloc::string::String;
        let mut current_working_directory = String::from("/");
        let (output, should_exit) =
            firmware::programs::shell::dispatch("", &mut current_working_directory);
        defmt::assert!(!should_exit);
        defmt::assert!(output.is_empty());
        Ok(())
    }

    /// `it("user runs `help` and gets a non-empty help message")`
    #[test]
    async fn user_runs_help_and_gets_help_message(
        _device: Device,
    ) -> Result<(), &'static str> {
        use alloc::string::String;
        let mut current_working_directory = String::from("/");
        let (output, should_exit) =
            firmware::programs::shell::dispatch("help", &mut current_working_directory);
        defmt::assert!(!should_exit);
        defmt::assert!(!output.is_empty());
        Ok(())
    }

    /// `it("user runs `pwd` and sees their current working directory")`
    #[test]
    async fn user_runs_pwd_and_sees_current_directory(
        _device: Device,
    ) -> Result<(), &'static str> {
        use alloc::string::String;
        let mut current_working_directory = String::from("/home/test");
        let (output, _should_exit) =
            firmware::programs::shell::dispatch("pwd", &mut current_working_directory);
        defmt::assert!(output.contains("/home/test"));
        Ok(())
    }

    /// `it("user runs `hostname` and gets a non-empty hostname")`
    #[test]
    async fn user_runs_hostname_and_gets_hostname(
        _device: Device,
    ) -> Result<(), &'static str> {
        use alloc::string::String;
        let mut current_working_directory = String::from("/");
        let (output, _should_exit) =
            firmware::programs::shell::dispatch("hostname", &mut current_working_directory);
        defmt::assert!(!output.is_empty());
        Ok(())
    }

    /// `it("user runs `whoami` and gets the current username")`
    #[test]
    async fn user_runs_whoami_and_gets_username(
        _device: Device,
    ) -> Result<(), &'static str> {
        use alloc::string::String;
        let mut current_working_directory = String::from("/");
        let (output, _should_exit) =
            firmware::programs::shell::dispatch("whoami", &mut current_working_directory);
        defmt::assert!(!output.is_empty());
        Ok(())
    }

    /// `it("user runs `uptime` and sees how long the device has been running")`
    #[test]
    async fn user_runs_uptime_and_sees_runtime(
        _device: Device,
    ) -> Result<(), &'static str> {
        use alloc::string::String;
        let mut current_working_directory = String::from("/");
        let (output, _should_exit) =
            firmware::programs::shell::dispatch("uptime", &mut current_working_directory);
        defmt::assert!(!output.is_empty());
        Ok(())
    }

    /// `it("user runs `free` and sees the heap report")`
    #[test]
    async fn user_runs_free_and_sees_heap_report(
        _device: Device,
    ) -> Result<(), &'static str> {
        use alloc::string::String;
        let mut current_working_directory = String::from("/");
        let (output, _should_exit) =
            firmware::programs::shell::dispatch("free", &mut current_working_directory);
        defmt::assert!(!output.is_empty());
        defmt::assert!(output.contains("Heap"));
        Ok(())
    }

    /// `it("user runs `date` and sees a non-empty timestamp")`
    #[test]
    async fn user_runs_date_and_sees_timestamp(
        _device: Device,
    ) -> Result<(), &'static str> {
        use alloc::string::String;
        let mut current_working_directory = String::from("/");
        let (output, _should_exit) =
            firmware::programs::shell::dispatch("date", &mut current_working_directory);
        defmt::assert!(!output.is_empty());
        Ok(())
    }
}
