pub mod filesystem_panel;
pub mod measurement_panel;
pub mod network_panel;

pub use filesystem_panel::FilesystemPanel;
pub use measurement_panel::MeasurementPanel;
pub use network_panel::NetworkPanel;

use dioxus::prelude::*;
use lucide_dioxus::{Database, File, FileCode, FileText, Image};

// ─── Shared types ───────────────────────────────────────────────────────────

#[derive(Clone, Copy, PartialEq)]
pub enum MeasurementTab {
    Voltage,
    Current,
    CarbonDioxide,
    TemperatureHumidity,
}

#[derive(Clone)]
pub struct Co2Row {
    pub row: usize,
    pub co2_ppm: f64,
    pub temperature: f64,
    pub humidity: f64,
    pub time: String,
}

#[derive(Clone)]
pub struct TemperatureHumidityReading {
    pub index: usize,
    pub read_ok: bool,
    pub temperature_celsius: f64,
    pub relative_humidity_percent: f64,
}

#[derive(Clone)]
pub struct TemperatureHumidityRow {
    pub row: usize,
    pub sensors: Vec<TemperatureHumidityReading>,
    pub time: String,
}

#[derive(Clone)]
pub struct VoltageRow {
    pub row: usize,
    pub gain: String,
    pub channels: Vec<f64>,
    pub time: String,
}

// ─── Feature flags ──────────────────────────────────────────────────────────

pub const ENABLE_VOLTAGE: bool = true;
pub const ENABLE_CURRENT: bool = false;
pub const ENABLE_CO2: bool = true;
pub const ENABLE_TEMPERATURE_HUMIDITY: bool = true;

// ─── Shared helpers ─────────────────────────────────────────────────────────

pub fn file_icon(name: &str) -> Element {
    let extension = name.rsplit('.').next().unwrap_or("").to_ascii_lowercase();
    match extension.as_str() {
        "js" | "rs" | "css" | "toml" => rsx! { FileCode { class: "w-4 h-4 text-primary" } },
        "html" | "htm" => rsx! { FileCode { class: "w-4 h-4 text-chart-3" } },
        "svg" | "png" | "jpg" => rsx! { Image { class: "w-4 h-4 text-chart-2" } },
        "db" | "csv" => rsx! { Database { class: "w-4 h-4 text-chart-4" } },
        "txt" | "log" | "md" => rsx! { FileText { class: "w-4 h-4 text-muted-foreground" } },
        "wasm" | "was" => rsx! { FileCode { class: "w-4 h-4 text-chart-5" } },
        _ => rsx! { File { class: "w-4 h-4 text-muted-foreground" } },
    }
}

pub fn now_time_string() -> String {
    js_sys::Date::new_0().to_locale_time_string("en-US").into()
}

pub async fn sleep_ms(milliseconds: u32) {
    gloo_timers::future::TimeoutFuture::new(milliseconds).await;
}

pub fn download_csv(filename: &str, csv_content: &str) {
    let escaped = csv_content.replace('`', "\\`").replace('\\', "\\\\");
    let javascript = format!(
        r#"(function(){{const b=new Blob([`{escaped}`],{{type:'text/csv'}});const a=document.createElement('a');a.href=URL.createObjectURL(b);a.download='{filename}';a.click();URL.revokeObjectURL(a.href)}})()"#,
    );
    document::eval(&javascript);
}

pub fn build_co2_csv(readings: &[Co2Row]) -> String {
    let mut csv = String::from("#,CO2_PPM,TEMP_C,HUMIDITY_PCT,TIME\n");
    for reading in readings {
        csv.push_str(&format!(
            "{},{},{},{},{}\n",
            reading.row, reading.co2_ppm, reading.temperature, reading.humidity, reading.time
        ));
    }
    csv
}

pub fn format_uptime(seconds: u64) -> String {
    let days = seconds / 86400;
    let hours = (seconds % 86400) / 3600;
    let minutes = (seconds % 3600) / 60;
    let secs = seconds % 60;
    if days > 0 {
        format!("{days}d {hours}h {minutes}m {secs}s")
    } else if hours > 0 {
        format!("{hours}h {minutes}m {secs}s")
    } else {
        format!("{minutes}m {secs}s")
    }
}

/// Fetch all sensor data from the CloudEvents endpoint and append rows.
/// Extracts CO2, temperature/humidity, and voltage events by type.
/// Returns true if any reading was added.
pub async fn fetch_and_add_sensor_readings(
    url: &str,
    mut co2_readings: Signal<Vec<Co2Row>>,
    mut temperature_humidity_readings: Signal<Vec<TemperatureHumidityRow>>,
    mut voltage_readings: Signal<Vec<VoltageRow>>,
) -> bool {
    let Ok(events) = crate::api::fetch_cloudevents(url).await else {
        return false;
    };

    let mut added = false;
    let time = now_time_string();

    for event in &events {
        let Some(data) = event.data.as_object() else { continue };

        match event.event_type.as_str() {
            // CO2 sensor (SCD30/SCD4x)
            t if t == "sensors.carbon_dioxide.v1" || data.contains_key("co2_ppm") => {
                let row = Co2Row {
                    row: co2_readings.read().len() + 1,
                    co2_ppm: data.get("co2_ppm").and_then(|value| value.as_f64()).unwrap_or(0.0),
                    temperature: data.get("temperature").and_then(|value| value.as_f64()).unwrap_or(0.0),
                    humidity: data.get("humidity").and_then(|value| value.as_f64()).unwrap_or(0.0),
                    time: time.clone(),
                };
                co2_readings.write().push(row);
                added = true;
            }

            // Temperature & humidity (CHT832X behind mux)
            "sensors.temperature_and_humidity.v1" => {
                if let Some(sensors) = data.get("sensors").and_then(|value| value.as_array()) {
                    let readings: Vec<TemperatureHumidityReading> = sensors.iter().map(|sensor| {
                        TemperatureHumidityReading {
                            index: sensor.get("index").and_then(|value| value.as_u64()).unwrap_or(0) as usize,
                            read_ok: sensor.get("read_ok").and_then(|value| value.as_bool()).unwrap_or(false),
                            temperature_celsius: sensor.get("temperature_celsius").and_then(|value| value.as_f64()).unwrap_or(0.0),
                            relative_humidity_percent: sensor.get("relative_humidity_percent").and_then(|value| value.as_f64()).unwrap_or(0.0),
                        }
                    }).collect();
                    let row = TemperatureHumidityRow {
                        row: temperature_humidity_readings.read().len() + 1,
                        sensors: readings,
                        time: time.clone(),
                    };
                    temperature_humidity_readings.write().push(row);
                    added = true;
                }
            }

            // Voltage monitor (ADS1115)
            "sensors.power.v1" => {
                if data.get("read_ok").and_then(|value| value.as_bool()) == Some(true) {
                    let channels = data.get("voltage")
                        .and_then(|value| value.as_array())
                        .map(|array| array.iter().filter_map(|value| value.as_f64()).collect())
                        .unwrap_or_default();
                    let gain = data.get("gain")
                        .and_then(|value| value.as_str())
                        .unwrap_or("")
                        .to_string();
                    let row = VoltageRow {
                        row: voltage_readings.read().len() + 1,
                        gain,
                        channels,
                        time: time.clone(),
                    };
                    voltage_readings.write().push(row);
                    added = true;
                }
            }

            _ => {}
        }
    }

    added
}

pub fn build_temperature_humidity_csv(readings: &[TemperatureHumidityRow]) -> String {
    if readings.is_empty() {
        return String::from("#,TIME\n");
    }
    let sensor_count = readings.first().map(|row| row.sensors.len()).unwrap_or(0);
    let mut csv = String::from("#,");
    for index in 0..sensor_count {
        csv.push_str(&format!("TEMP_{index}_C,RH_{index}_PCT,"));
    }
    csv.push_str("TIME\n");
    for row in readings {
        csv.push_str(&format!("{},", row.row));
        for sensor in &row.sensors {
            if sensor.read_ok {
                csv.push_str(&format!("{},{},", sensor.temperature_celsius, sensor.relative_humidity_percent));
            } else {
                csv.push_str(",,");
            }
        }
        csv.push_str(&format!("{}\n", row.time));
    }
    csv
}

pub fn build_voltage_csv(readings: &[VoltageRow]) -> String {
    let mut csv = String::from("#,CH0_V,CH1_V,CH2_V,CH3_V,TIME\n");
    for row in readings {
        csv.push_str(&format!("{},", row.row));
        for (index, voltage) in row.channels.iter().enumerate() {
            csv.push_str(&format!("{voltage:.4}"));
            if index < row.channels.len() - 1 {
                csv.push(',');
            }
        }
        csv.push_str(&format!(",{}\n", row.time));
    }
    csv
}

// ─── Shared UI components ───────────────────────────────────────────────────

pub fn tab_button(mut active_tab: Signal<MeasurementTab>, tab: MeasurementTab, label: &'static str) -> Element {
    let is_active = *active_tab.read() == tab;
    let class = if is_active {
        "flex-1 py-2 text-center rounded-full border border-border bg-background text-foreground font-medium transition-all duration-200"
    } else {
        "flex-1 py-2 text-center rounded-full text-muted-foreground hover:text-foreground transition-all duration-200"
    };
    rsx! {
        button {
            class: class,
            onclick: move |_| active_tab.set(tab),
            "{label}"
        }
    }
}

#[component]
pub fn LiveIndicator(connected: bool) -> Element {
    let (dot_class, ping_class, label) = if connected {
        ("bg-emerald-400", "absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-70 animate-ping", "LIVE")
    } else {
        ("bg-amber-500", "absolute inline-flex h-full w-full rounded-full bg-amber-500 opacity-70 animate-pulse", "POLLING")
    };
    rsx! {
        div { class: "flex items-center gap-2 rounded-full border border-border bg-background/60 px-3 py-1.5 text-xs text-muted-foreground shrink-0",
            span { class: "relative flex h-2 w-2",
                span { class: "{ping_class}" }
                span { class: "relative inline-flex h-2 w-2 rounded-full {dot_class}" }
            }
            span { class: "font-medium text-foreground", "{label}" }
        }
    }
}

#[component]
pub fn StatusBadge(icon: Element, value: String) -> Element {
    rsx! {
        span { class: "inline-flex items-center gap-1.5 rounded-full border border-border bg-background/60 px-2.5 py-1 text-xs font-mono text-foreground",
            {icon}
            "{value}"
        }
    }
}

#[component]
pub fn Th(children: Element) -> Element {
    rsx! {
        th { class: "text-left px-3 py-2 border-b border-border text-muted-foreground text-xs uppercase tracking-wider sticky top-0 bg-muted whitespace-nowrap",
            {children}
        }
    }
}

#[component]
pub fn Td(children: Element, class: Option<String>) -> Element {
    let extra = class.unwrap_or_default();
    rsx! {
        td { class: "px-3 py-2 text-sm {extra}", {children} }
    }
}
