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
}

#[derive(Clone)]
pub struct Co2Row {
    pub row: usize,
    pub co2_ppm: f64,
    pub temperature: f64,
    pub humidity: f64,
    pub time: String,
}

// ─── Feature flags ──────────────────────────────────────────────────────────

pub const ENABLE_VOLTAGE: bool = false;
pub const ENABLE_CURRENT: bool = false;
pub const ENABLE_CO2: bool = true;

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

/// Fetch CO2 data from the cloudevents endpoint and append a row.
/// Returns true if a reading was added.
pub async fn fetch_and_add_co2_reading(
    url: &str,
    mut co2_readings: Signal<Vec<Co2Row>>,
) -> bool {
    if let Ok(events) = crate::api::fetch_cloudevents(url).await {
        for event in &events {
            if let Some(data) = event.data.as_object() {
                if data.contains_key("co2_ppm") {
                    let row = Co2Row {
                        row: co2_readings.read().len() + 1,
                        co2_ppm: data.get("co2_ppm").and_then(|value| value.as_f64()).unwrap_or(0.0),
                        temperature: data.get("temperature").and_then(|value| value.as_f64()).unwrap_or(0.0),
                        humidity: data.get("humidity").and_then(|value| value.as_f64()).unwrap_or(0.0),
                        time: now_time_string(),
                    };
                    co2_readings.write().push(row);
                    return true;
                }
            }
        }
    }
    false
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
