use alloc::string::String as AllocString;
use core::fmt::Write;
use embassy_time::Instant;
use esp_hal::{clock, efuse, system, system::Cpu};

use crate::{
    config::{app, board},
    console::icons,
    hardware,
    services::{identity, system as system_service},
};

unsafe extern "C" {
    #[link_name = "esp_app_desc"]
    static ESP_APP_DESC: esp_bootloader_esp_idf::EspAppDesc;
}

// TODO(perf): The 30+ row!() invocations below are repetitive but each
// has different format arguments, so a data-driven array of tuples would
// require pre-formatting each value into an AllocString (one heap
// allocation per row). On PSRAM that's tolerable but wasteful. The
// current approach writes directly to a single output buffer with zero
// intermediate allocations. Refactor only if readability becomes a
// maintenance burden — the format arguments are type-checked at compile
// time, which a data-driven approach would lose.
macro_rules! row {
    ($out:expr, $color:expr, $icon:expr, $label:expr, $($val:tt)*) => {{
        let _ = write!($out, "  \x1b[1;{}m{} {:<14}\x1b[0m ", $color, $icon, $label);
        let _ = write!($out, $($val)*);
        let _ = write!($out, "\r\n");
    }};
}

pub fn run() -> AllocString {
    let mut out = AllocString::new();
    let secs = Instant::now().as_secs();
    let system_snapshot = system_service::snapshot();
    let sensor_inventory = &system_snapshot.sensors.inventory;
    let carbon_dioxide = system_snapshot.sensors.carbon_dioxide;
    let i2c_status = hardware::i2c::snapshot();
    let chip_rev = efuse::chip_revision();
    let mac = efuse::base_mac_address();
    let cpu_freq_mhz = clock::cpu_clock().as_mhz();

    let heap_used = esp_alloc::HEAP.used();
    let heap_free = esp_alloc::HEAP.free();
    let heap_total = heap_used + heap_free;
    let heap_pct = (heap_used * 100) / heap_total;

    let _ = write!(out, "\r\n");

    let _ = write!(
        out,
        "  \x1b[1;32m{}\x1b[0m\x1b[2m@\x1b[0m\x1b[1;36m{}\x1b[0m\r\n",
        identity::ssh_user(),
        identity::hostname()
    );
    let sep_len = identity::ssh_user().len() + 1 + identity::hostname().len();
    let _ = write!(out, "  \x1b[2m");
    for _ in 0..sep_len {
        out.push(icons::BOX_HORIZONTAL);
    }
    let _ = write!(out, "\x1b[0m\r\n");

    let app_desc = unsafe { &ESP_APP_DESC };
    row!(
        out,
        "33",
        "",
        "OS",
        "\x1b[1m{}\x1b[0m {} ({})",
        app_desc.project_name(),
        app_desc.version(),
        board::PLATFORM
    );
    row!(
        out,
        "35",
        "",
        "Host",
        "\x1b[1mESP32-S3\x1b[0m (rev {}.{})",
        chip_rev.major,
        chip_rev.minor
    );
    row!(
        out,
        "35",
        "",
        "Chassis",
        "\x1b[1mesp32s3-devkitc1-N8R8\x1b[0m"
    );
    row!(
        out,
        "36",
        "",
        "Kernel",
        "\x1b[1membassy 0.7\x1b[0m / esp-hal 1.0"
    );
    row!(
        out,
        "33",
        icons::NF_FA_DATABASE,
        "Built",
        "\x1b[1m{}\x1b[0m {}",
        app_desc.date(),
        app_desc.time()
    );
    {
        let mut buf = [0u8; esp_bootloader_esp_idf::partitions::PARTITION_TABLE_MAX_LEN];
        let mut flash = esp_storage::FlashStorage::new();
        if let Ok(pt) =
            esp_bootloader_esp_idf::partitions::read_partition_table(&mut flash, &mut buf)
        {
            if let Ok(Some(entry)) = pt.booted_partition() {
                row!(
                    out,
                    "34",
                    icons::NF_FA_HDD,
                    "Partition",
                    "\x1b[1m{}\x1b[0m",
                    entry.label_as_str()
                );
            }
        }
    }

    let (d, h, m, s) = (
        secs / 86400,
        (secs % 86400) / 3600,
        (secs % 3600) / 60,
        secs % 60,
    );
    match (d, h) {
        (1.., _) => row!(
            out,
            "34",
            "",
            "Uptime",
            "\x1b[1m{}\x1b[0m days, \x1b[1m{}\x1b[0m hours, \x1b[1m{}\x1b[0m mins, \x1b[1m{}\x1b[0m secs",
            d,
            h,
            m,
            s
        ),
        (_, 1..) => row!(
            out,
            "34",
            "",
            "Uptime",
            "\x1b[1m{}\x1b[0m hours, \x1b[1m{}\x1b[0m mins, \x1b[1m{}\x1b[0m secs",
            h,
            m,
            s
        ),
        _ => row!(
            out,
            "34",
            "",
            "Uptime",
            "\x1b[1m{}\x1b[0m mins, \x1b[1m{}\x1b[0m secs",
            m,
            s
        ),
    }

    if let Some(reason) = system::reset_reason() {
        row!(
            out,
            "31",
            icons::NF_FA_BOLT,
            "Reset",
            "\x1b[1m{:?}\x1b[0m",
            reason
        );
    }

    row!(out, "32", "", "Shell", "\x1b[1mMicroshell\x1b[0m (SSH)");
    row!(
        out,
        "31",
        "",
        "CPU",
        "\x1b[1mXtensa LX7\x1b[0m ({}) @ \x1b[1m{} MHz\x1b[0m",
        Cpu::COUNT,
        cpu_freq_mhz
    );
    row!(
        out,
        "36",
        "",
        "RAM",
        "\x1b[1m{:.2} KiB\x1b[0m / \x1b[1m{:.2} KiB\x1b[0m (\x1b[1;32m{}%\x1b[0m)",
        heap_used as f32 / 1024.0,
        heap_total as f32 / 1024.0,
        heap_pct
    );

    if system_snapshot.storage.sd_card_size_mb > 0 {
        row!(
            out,
            "32",
            "",
            "Disk",
            "\x1b[1m{} MiB\x1b[0m / \x1b[1m{} MiB\x1b[0m - {} [\x1b[1m{}\x1b[0m]",
            0,
            system_snapshot.storage.sd_card_size_mb,
            app::sd_card::FS_TYPE,
            app::sd_card::DEVICE
        );
    } else {
        row!(
            out,
            "32",
            icons::NF_FA_HDD,
            "Disk",
            "\x1b[2mnot detected\x1b[0m"
        );
    }

    row!(
        out,
        "33",
        "",
        "Local IP",
        "\x1b[1m{}.{}.{}.{}\x1b[0m/24",
        system_snapshot.network.station.ipv4_address[0],
        system_snapshot.network.station.ipv4_address[1],
        system_snapshot.network.station.ipv4_address[2],
        system_snapshot.network.station.ipv4_address[3]
    );
    row!(
        out,
        "32",
        icons::NF_FA_WIFI,
        "WiFi STA",
        "{}",
        if system_snapshot.network.station.is_connected {
            "\x1b[32mconnected\x1b[0m"
        } else {
            "\x1b[31mdisconnected\x1b[0m"
        }
    );
    row!(
        out,
        "35",
        "",
        "MAC",
        "\x1b[1m{:02X}:{:02X}:{:02X}:{:02X}:{:02X}:{:02X}\x1b[0m",
        mac.as_bytes()[0],
        mac.as_bytes()[1],
        mac.as_bytes()[2],
        mac.as_bytes()[3],
        mac.as_bytes()[4],
        mac.as_bytes()[5]
    );

    let _ = write!(out, "\r\n");

    row!(
        out,
        "36",
        icons::NF_FA_SERVER,
        "Hostname",
        "\x1b[1m{}\x1b[0m",
        identity::hostname()
    );
    row!(
        out,
        "34",
        icons::NF_FA_GLOBE,
        "NTP",
        "\x1b[1m{}\x1b[0m",
        app::NTP_SERVER
    );
    row!(
        out,
        "33",
        icons::NF_FA_PLUG,
        "Ports",
        "SSH:\x1b[1m{}\x1b[0m  HTTP:\x1b[1m{}\x1b[0m  OTA:\x1b[1m{}\x1b[0m  Log:\x1b[1m{}\x1b[0m",
        app::ssh::PORT,
        app::http::PORT,
        app::ota::PORT,
        app::tcp_log::PORT
    );
    row!(
        out,
        "35",
        icons::NF_FA_WIFI,
        "WiFi AP",
        "\x1b[1m{}\x1b[0m (ch\x1b[1m{}\x1b[0m, {})",
        system_snapshot.network.access_point.ssid,
        system_snapshot.network.access_point.channel,
        system_snapshot.network.access_point.auth_mode
    );

    let _ = write!(out, "\r\n");

    row!(
        out,
        "36",
        icons::NF_FA_COG,
        "I2C Freq",
        "\x1b[1m{}\x1b[0m kHz",
        i2c_status.frequency_khz
    );
    row!(
        out,
        "31",
        icons::NF_FA_BOLT,
        "Power GPIO",
        "\x1b[1mGPIO{}\x1b[0m",
        i2c_status.power_gpio
    );
    row!(
        out,
        "34",
        icons::NF_FA_COG,
        "SPI (SD)",
        "CS:\x1b[1mGPIO{}\x1b[0m  MOSI:\x1b[1mGPIO{}\x1b[0m  SCK:\x1b[1mGPIO{}\x1b[0m  MISO:\x1b[1mGPIO{}\x1b[0m",
        board::sd_card::CS_GPIO,
        board::sd_card::MOSI_GPIO,
        board::sd_card::SCK_GPIO,
        board::sd_card::MISO_GPIO
    );

    for bus in i2c_status.buses.iter() {
        row!(
            out,
            "36",
            icons::NF_FA_SITEMAP,
            bus.name,
            "SDA:\x1b[1mGPIO{}\x1b[0m  SCL:\x1b[1mGPIO{}\x1b[0m",
            bus.sda_gpio,
            bus.scl_gpio
        );
    }

    let _ = write!(out, "\r\n");

    for sensor in sensor_inventory.iter() {
        let mut val = AllocString::new();
        let transport = sensor.transport_summary();
        if let Some(address) = transport.address {
            let _ = write!(
                val,
                "\x1b[1m{}\x1b[0m @ {} (\x1b[1m0x{:02X}\x1b[0m)",
                sensor.model, transport.bus_name, address
            );
        } else {
            let _ = write!(
                val,
                "\x1b[1m{}\x1b[0m @ {} (slave \x1b[1m{}\x1b[0m reg \x1b[1m{}\x1b[0m)",
                sensor.model,
                transport.bus_name,
                transport.slave_id.unwrap_or_default(),
                transport.register_address.unwrap_or_default()
            );
        }
        row!(out, "35", icons::NF_FA_SIGNAL, sensor.name, "{}", val);
    }

    if carbon_dioxide.ok {
        let _ = write!(out, "\r\n");
        row!(
            out,
            "32",
            icons::NF_FA_LEAF,
            "CO2",
            "\x1b[1;32m{:.1}\x1b[0m ppm",
            carbon_dioxide.co2_ppm
        );
        row!(
            out,
            "31",
            icons::NF_FA_THERMOMETER,
            "Temperature",
            "\x1b[1;33m{:.1}\x1b[0m\u{00b0}C",
            carbon_dioxide.temperature
        );
        row!(
            out,
            "34",
            icons::NF_FA_TINT,
            "Humidity",
            "\x1b[1;36m{:.1}\x1b[0m%%",
            carbon_dioxide.humidity
        );
    }

    let _ = write!(out, "\r\n");
    out
}
