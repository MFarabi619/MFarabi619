use crate::api::{self, Co2ConfigData};
use super::{
    build_co2_csv, build_temperature_humidity_csv, build_voltage_csv,
    download_csv, fetch_and_add_sensor_readings, now_time_string, tab_button,
    Co2Row, TemperatureHumidityRow, VoltageRow, MeasurementTab, Th, Td,
    ENABLE_CO2, ENABLE_CURRENT, ENABLE_VOLTAGE, ENABLE_TEMPERATURE_HUMIDITY,
};
use dioxus::prelude::*;
use lucide_dioxus::{Download, LoaderCircle};
use ui::components::toast::Toasts;

#[component]
pub fn MeasurementPanel(
    device_url: Signal<String>,
    co2_readings: Signal<Vec<Co2Row>>,
    temperature_humidity_readings: Signal<Vec<TemperatureHumidityRow>>,
    voltage_readings: Signal<Vec<VoltageRow>>,
    co2_config: Signal<Option<Co2ConfigData>>,
    sampling: Signal<bool>,
    active_tab: Signal<MeasurementTab>,
) -> Element {
    let toasts = Toasts;
    let mut show_toast = move |message: String, kind: &'static str| {
        match kind {
            "ok" => toasts.success(message, None),
            "err" => toasts.error(message, None),
            _ => toasts.info(message, None),
        }
    };

    rsx! {
        section { id: "cloudevents-section", class: "border border-border rounded-2xl bg-card p-4",
            nav { class: "flex w-full border border-border rounded-full p-1 mb-4",
                if ENABLE_TEMPERATURE_HUMIDITY {
                    {tab_button(active_tab, MeasurementTab::TemperatureHumidity, "Temp/Humidity")}
                }
                if ENABLE_VOLTAGE {
                    {tab_button(active_tab, MeasurementTab::Voltage, "Voltage")}
                }
                if ENABLE_CURRENT {
                    {tab_button(active_tab, MeasurementTab::Current, "Current")}
                }
                if ENABLE_CO2 {
                    {tab_button(active_tab, MeasurementTab::CarbonDioxide, "CO₂")}
                }
            }

            // CO2 panel
            if ENABLE_CO2 && *active_tab.read() == MeasurementTab::CarbonDioxide {
                div {
                    // Inline toolbar: badge + controls + CSV + Sample
                    div { class: "flex items-center gap-2 flex-wrap mb-3",
                        if let Some(ref config) = *co2_config.read() {
                            span { class: "text-xs font-mono text-muted-foreground border border-border rounded px-1.5 py-0.5", "{config.model}" }

                            button {
                                class: "text-xs border border-border rounded px-1.5 py-0.5 flex items-center gap-1 transition-colors hover:bg-muted/50",
                                onclick: move |_| {
                                    let url = device_url.read().clone();
                                    let is_measuring = co2_config.read().as_ref().map(|c| c.measuring).unwrap_or(false);
                                    spawn(async move {
                                        if is_measuring { let _ = api::stop_co2(&url).await; }
                                        else { let _ = api::start_co2(&url).await; }
                                        if let Ok(response) = api::fetch_co2_config(&url).await {
                                            co2_config.set(Some(response.data));
                                        }
                                    });
                                },
                                if config.measuring {
                                    span { class: "w-1.5 h-1.5 rounded-full bg-emerald-400" }
                                    "{config.measurement_interval_seconds}s"
                                } else {
                                    span { class: "w-1.5 h-1.5 rounded-full bg-red-400" }
                                    "stopped"
                                }
                            }

                            // Inline config controls (no accordion)
                            div { class: "hidden sm:flex items-center gap-2",
                                input {
                                    class: "w-14 px-1.5 py-0.5 rounded border border-border bg-background text-foreground text-xs text-center",
                                    r#type: "number", min: "2", max: "1800",
                                    title: "Measurement interval (seconds)",
                                    value: "{config.measurement_interval_seconds}",
                                    onchange: move |event| {
                                        if let Ok(seconds) = event.value().parse::<u16>() {
                                            let url = device_url.read().clone();
                                            spawn(async move {
                                                let _ = api::set_co2_config(&url, &serde_json::json!({"measurement_interval_seconds": seconds})).await;
                                                if let Ok(response) = api::fetch_co2_config(&url).await { co2_config.set(Some(response.data)); }
                                            });
                                        }
                                    },
                                }
                                span { class: "text-xs text-muted-foreground", "s" }

                                label { class: "flex items-center gap-1 text-xs text-muted-foreground cursor-pointer",
                                    title: "Auto-calibration (ASC)",
                                    input {
                                        r#type: "checkbox", class: "accent-primary",
                                        checked: config.auto_calibration_enabled,
                                        onchange: move |event| {
                                            let enabled = event.checked();
                                            let url = device_url.read().clone();
                                            spawn(async move {
                                                let _ = api::set_co2_config(&url, &serde_json::json!({"auto_calibration_enabled": enabled})).await;
                                                if let Ok(response) = api::fetch_co2_config(&url).await { co2_config.set(Some(response.data)); }
                                            });
                                        },
                                    }
                                    "ASC"
                                }

                                input {
                                    class: "w-12 px-1.5 py-0.5 rounded border border-border bg-background text-foreground text-xs text-center",
                                    r#type: "number", step: "0.1", min: "0", max: "50",
                                    title: "Temperature offset (°C)",
                                    value: "{config.temperature_offset_celsius}",
                                    onchange: move |event| {
                                        if let Ok(offset) = event.value().parse::<f64>() {
                                            let url = device_url.read().clone();
                                            spawn(async move {
                                                let _ = api::set_co2_config(&url, &serde_json::json!({"temperature_offset_celsius": offset})).await;
                                                if let Ok(response) = api::fetch_co2_config(&url).await { co2_config.set(Some(response.data)); }
                                            });
                                        }
                                    },
                                }
                                span { class: "text-xs text-muted-foreground", "\u{00b0}C" }

                                input {
                                    class: "w-14 px-1.5 py-0.5 rounded border border-border bg-background text-foreground text-xs text-center",
                                    r#type: "number", min: "0", max: "10000",
                                    title: "Altitude compensation (m)",
                                    value: "{config.altitude_meters}",
                                    onchange: move |event| {
                                        if let Ok(altitude) = event.value().parse::<u16>() {
                                            let url = device_url.read().clone();
                                            spawn(async move {
                                                let _ = api::set_co2_config(&url, &serde_json::json!({"altitude_meters": altitude})).await;
                                                if let Ok(response) = api::fetch_co2_config(&url).await { co2_config.set(Some(response.data)); }
                                            });
                                        }
                                    },
                                }
                                span { class: "text-xs text-muted-foreground", "m" }
                            }
                        } else {
                            span { class: "text-xs text-muted-foreground", "(polling every 5s)" }
                        }

                        div { class: "flex-1" }

                        if !co2_readings.read().is_empty() {
                            button {
                                class: "px-3 py-2 rounded-lg border border-border text-foreground flex items-center gap-2 transition-colors hover:bg-muted/70 text-sm",
                                onclick: move |_| {
                                    let csv = build_co2_csv(&co2_readings.read());
                                    download_csv("co2_readings.csv", &csv);
                                },
                                Download { class: "w-4 h-4" }
                                "CSV"
                            }
                        }

                        button {
                            class: "px-4 py-2 rounded-lg bg-accent text-accent-foreground flex items-center gap-2 transition-colors hover:bg-accent/85",
                            disabled: *sampling.read(),
                            onclick: move |_| {
                                sampling.set(true);
                                let url = device_url.read().clone();
                                spawn(async move {
                                    fetch_and_add_sensor_readings(
                                        &url, co2_readings, temperature_humidity_readings, voltage_readings,
                                    ).await;
                                    sampling.set(false);
                                });
                            },
                            if *sampling.read() {
                                LoaderCircle { class: "w-4 h-4 animate-spin" }
                                "Sampling..."
                            } else {
                                lucide_dioxus::FlaskConical { class: "w-4 h-4" }
                                "Sample"
                                span { class: "text-xs text-muted-foreground bg-muted px-1.5 py-0.5 rounded", "C+\u{21b5}" }
                            }
                        }
                    }

                    // Data table
                    div { class: "border border-border rounded-lg overflow-hidden",
                        div { class: "w-full overflow-x-auto max-h-[300px]",
                            table { class: "min-w-full border-collapse",
                                thead { class: "bg-muted",
                                    tr {
                                        Th { "#" }
                                        Th { "PPM" }
                                        Th { "\u{00b0}C" }
                                        Th { "%" }
                                        Th { "TIME" }
                                    }
                                }
                                tbody {
                                    if co2_readings.read().is_empty() {
                                        tr {
                                            td { colspan: "5", class: "px-4 py-10 text-center",
                                                div { class: "flex flex-col items-center gap-2",
                                                    lucide_dioxus::Wind { class: "w-9 h-9 text-muted-foreground" }
                                                    h3 { class: "text-sm font-medium text-foreground", "No readings yet" }
                                                    p { class: "text-sm text-muted-foreground", "Data streams automatically every 5 seconds" }
                                                }
                                            }
                                        }
                                    }
                                    for row in co2_readings.read().iter().rev() {
                                        tr { class: "border-b border-border hover:bg-muted/40 transition-colors",
                                            Td { "{row.row}" }
                                            Td { class: "tabular-nums", "{row.co2_ppm:.0}" }
                                            Td { class: "tabular-nums", "{row.temperature:.1}" }
                                            Td { class: "tabular-nums", "{row.humidity:.1}" }
                                            Td { class: "text-muted-foreground whitespace-nowrap", "{row.time}" }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Temperature & Humidity panel
            if ENABLE_TEMPERATURE_HUMIDITY && *active_tab.read() == MeasurementTab::TemperatureHumidity {
                div {
                    div { class: "flex items-center gap-2 flex-wrap mb-3",
                        span { class: "text-xs font-mono text-muted-foreground border border-border rounded px-1.5 py-0.5", "CHT832X" }
                        div { class: "flex-1" }

                        if !temperature_humidity_readings.read().is_empty() {
                            button {
                                class: "px-3 py-2 rounded-lg border border-border text-foreground flex items-center gap-2 transition-colors hover:bg-muted/70 text-sm",
                                onclick: move |_| {
                                    let csv = build_temperature_humidity_csv(&temperature_humidity_readings.read());
                                    download_csv("temperature_humidity.csv", &csv);
                                },
                                Download { class: "w-4 h-4" }
                                "CSV"
                            }
                        }

                        button {
                            class: "px-4 py-2 rounded-lg bg-accent text-accent-foreground flex items-center gap-2 transition-colors hover:bg-accent/85",
                            disabled: *sampling.read(),
                            onclick: move |_| {
                                sampling.set(true);
                                let url = device_url.read().clone();
                                spawn(async move {
                                    fetch_and_add_sensor_readings(
                                        &url, co2_readings, temperature_humidity_readings, voltage_readings,
                                    ).await;
                                    sampling.set(false);
                                });
                            },
                            if *sampling.read() {
                                LoaderCircle { class: "w-4 h-4 animate-spin" }
                                "Sampling..."
                            } else {
                                lucide_dioxus::Thermometer { class: "w-4 h-4" }
                                "Sample"
                                span { class: "text-xs text-muted-foreground bg-muted px-1.5 py-0.5 rounded", "C+\u{21b5}" }
                            }
                        }
                    }

                    div { class: "border border-border rounded-lg overflow-hidden",
                        div { class: "w-full overflow-x-auto max-h-[300px]",
                            table { class: "min-w-full border-collapse",
                                thead { class: "bg-muted",
                                    tr {
                                        Th { "#" }
                                        {
                                            let sensor_count = temperature_humidity_readings.read()
                                                .first()
                                                .map(|row| row.sensors.len())
                                                .unwrap_or(0);
                                            (0..sensor_count).map(|index| {
                                                rsx! {
                                                    Th { "\u{00b0}C {index}" }
                                                    Th { "% {index}" }
                                                }
                                            })
                                        }
                                        Th { "TIME" }
                                    }
                                }
                                tbody {
                                    if temperature_humidity_readings.read().is_empty() {
                                        tr {
                                            td { colspan: "5", class: "px-4 py-10 text-center",
                                                div { class: "flex flex-col items-center gap-2",
                                                    lucide_dioxus::Thermometer { class: "w-9 h-9 text-muted-foreground" }
                                                    h3 { class: "text-sm font-medium text-foreground", "No readings yet" }
                                                    p { class: "text-sm text-muted-foreground", "Data streams automatically every 5 seconds" }
                                                }
                                            }
                                        }
                                    }
                                    for row in temperature_humidity_readings.read().iter().rev() {
                                        tr { class: "border-b border-border hover:bg-muted/40 transition-colors",
                                            Td { "{row.row}" }
                                            for sensor in row.sensors.iter() {
                                                if sensor.read_ok {
                                                    Td { class: "tabular-nums", "{sensor.temperature_celsius:.1}" }
                                                    Td { class: "tabular-nums", "{sensor.relative_humidity_percent:.1}" }
                                                } else {
                                                    Td { class: "text-muted-foreground", "—" }
                                                    Td { class: "text-muted-foreground", "—" }
                                                }
                                            }
                                            Td { class: "text-muted-foreground whitespace-nowrap", "{row.time}" }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Voltage panel
            if ENABLE_VOLTAGE && *active_tab.read() == MeasurementTab::Voltage {
                div {
                    div { class: "flex items-center gap-2 flex-wrap mb-3",
                        span { class: "text-xs font-mono text-muted-foreground border border-border rounded px-1.5 py-0.5", "ADS1115" }
                        if let Some(ref row) = voltage_readings.read().last() {
                            span { class: "text-xs font-mono text-muted-foreground border border-border rounded px-1.5 py-0.5", "{row.gain}" }
                        }
                        div { class: "flex-1" }

                        if !voltage_readings.read().is_empty() {
                            button {
                                class: "px-3 py-2 rounded-lg border border-border text-foreground flex items-center gap-2 transition-colors hover:bg-muted/70 text-sm",
                                onclick: move |_| {
                                    let csv = build_voltage_csv(&voltage_readings.read());
                                    download_csv("voltage.csv", &csv);
                                },
                                Download { class: "w-4 h-4" }
                                "CSV"
                            }
                        }

                        button {
                            class: "px-4 py-2 rounded-lg bg-accent text-accent-foreground flex items-center gap-2 transition-colors hover:bg-accent/85",
                            disabled: *sampling.read(),
                            onclick: move |_| {
                                sampling.set(true);
                                let url = device_url.read().clone();
                                spawn(async move {
                                    fetch_and_add_sensor_readings(
                                        &url, co2_readings, temperature_humidity_readings, voltage_readings,
                                    ).await;
                                    sampling.set(false);
                                });
                            },
                            if *sampling.read() {
                                LoaderCircle { class: "w-4 h-4 animate-spin" }
                                "Sampling..."
                            } else {
                                lucide_dioxus::Zap { class: "w-4 h-4" }
                                "Sample"
                                span { class: "text-xs text-muted-foreground bg-muted px-1.5 py-0.5 rounded", "C+\u{21b5}" }
                            }
                        }
                    }

                    div { class: "border border-border rounded-lg overflow-hidden",
                        div { class: "w-full overflow-x-auto max-h-[300px]",
                            table { class: "min-w-full border-collapse",
                                thead { class: "bg-muted",
                                    tr {
                                        Th { "#" }
                                        Th { "CH0 (V)" }
                                        Th { "CH1 (V)" }
                                        Th { "CH2 (V)" }
                                        Th { "CH3 (V)" }
                                        Th { "TIME" }
                                    }
                                }
                                tbody {
                                    if voltage_readings.read().is_empty() {
                                        tr {
                                            td { colspan: "6", class: "px-4 py-10 text-center",
                                                div { class: "flex flex-col items-center gap-2",
                                                    lucide_dioxus::Zap { class: "w-9 h-9 text-muted-foreground" }
                                                    h3 { class: "text-sm font-medium text-foreground", "No readings yet" }
                                                    p { class: "text-sm text-muted-foreground", "Data streams automatically every 5 seconds" }
                                                }
                                            }
                                        }
                                    }
                                    for row in voltage_readings.read().iter().rev() {
                                        tr { class: "border-b border-border hover:bg-muted/40 transition-colors",
                                            Td { "{row.row}" }
                                            for voltage in row.channels.iter() {
                                                Td { class: "tabular-nums", "{voltage:.4}" }
                                            }
                                            Td { class: "text-muted-foreground whitespace-nowrap", "{row.time}" }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
