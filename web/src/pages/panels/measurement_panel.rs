use crate::api::{self, Co2ConfigData};
use super::{
    build_co2_csv, download_csv, fetch_and_add_co2_reading, now_time_string, tab_button,
    Co2Row, MeasurementTab, Th, Td,
    ENABLE_CO2, ENABLE_CURRENT, ENABLE_VOLTAGE,
};
use dioxus::prelude::*;
use lucide_dioxus::{
    ChevronDown, ChevronRight, Download, LoaderCircle, Play, Settings, Square,
};
use ui::components::toast::Toasts;

#[component]
pub fn MeasurementPanel(
    device_url: Signal<String>,
    co2_readings: Signal<Vec<Co2Row>>,
    co2_config: Signal<Option<Co2ConfigData>>,
    co2_settings_open: Signal<bool>,
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
                    // Header with inline controls
                    div { class: "flex items-center gap-2 flex-wrap mb-3",
                        h2 { class: "text-xl font-semibold", "Carbon Dioxide" }

                        if let Some(ref config) = *co2_config.read() {
                            span { class: "text-xs font-mono text-muted-foreground border border-border rounded px-1.5 py-0.5", "{config.model}" }

                            button {
                                class: "text-xs border border-border rounded px-1.5 py-0.5 flex items-center gap-1 transition-colors hover:bg-muted/50",
                                onclick: move |_| {
                                    let url = device_url.read().clone();
                                    let is_measuring = co2_config.read().as_ref().map(|configuration| configuration.measuring).unwrap_or(false);
                                    spawn(async move {
                                        if is_measuring {
                                            let _ = api::stop_co2(&url).await;
                                        } else {
                                            let _ = api::start_co2(&url).await;
                                        }
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

                            button {
                                class: "text-muted-foreground hover:text-foreground transition-colors p-0.5",
                                onclick: move |_| {
                                    let currently_open = *co2_settings_open.peek();
                                    co2_settings_open.set(!currently_open);
                                },
                                Settings { class: "w-4 h-4" }
                            }
                        } else {
                            span { class: "text-xs text-muted-foreground", "(polling every 5s)" }
                        }

                        a {
                            class: "text-muted-foreground hover:text-foreground transition-colors p-0.5",
                            href: "{device_url}/SCD30.PDF",
                            target: "_blank",
                            title: "SCD30 Datasheet",
                            lucide_dioxus::FileText { class: "w-4 h-4" }
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
                                    fetch_and_add_co2_reading(&url, co2_readings).await;
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
                                        Th { "CO2 (ppm)" }
                                        Th { "TEMP (C)" }
                                        Th { "HUMIDITY (%)" }
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

                    // Settings toggle
                    button {
                        class: "mt-3 w-full flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition-colors py-2",
                        onclick: move |_| {
                            let currently_open = *co2_settings_open.read();
                            co2_settings_open.set(!currently_open);
                            if !currently_open {
                                let url = device_url.read().clone();
                                spawn(async move {
                                    if let Ok(response) = api::fetch_co2_config(&url).await {
                                        co2_config.set(Some(response.data));
                                    }
                                });
                            }
                        },
                        Settings { class: "w-4 h-4" }
                        "Sensor Settings"
                        if *co2_settings_open.read() {
                            ChevronDown { class: "w-4 h-4 ml-auto" }
                        } else {
                            ChevronRight { class: "w-4 h-4 ml-auto" }
                        }
                    }

                    // Settings panel
                    if *co2_settings_open.read() {
                        div { class: "mt-2 border border-border rounded-lg p-4 space-y-3",
                            if let Some(ref config) = *co2_config.read() {
                                {
                                let is_scd30 = config.model == "SCD30";
                                let disabled_class = if is_scd30 { "" } else { " opacity-40 pointer-events-none" };

                                rsx! {
                                div { class: "flex items-center justify-between",
                                    span { class: "text-sm", "Measurement" }
                                    button {
                                        class: "px-3 py-1.5 rounded-lg border border-border text-sm flex items-center gap-2 transition-colors hover:bg-muted/50",
                                        onclick: move |_| {
                                            let url = device_url.read().clone();
                                            let is_measuring = co2_config.read().as_ref().map(|configuration| configuration.measuring).unwrap_or(false);
                                            spawn(async move {
                                                if is_measuring {
                                                    let _ = api::stop_co2(&url).await;
                                                } else {
                                                    let _ = api::start_co2(&url).await;
                                                }
                                                if let Ok(response) = api::fetch_co2_config(&url).await {
                                                    co2_config.set(Some(response.data));
                                                }
                                            });
                                        },
                                        if config.measuring {
                                            Square { class: "w-3.5 h-3.5 text-destructive" }
                                            "Stop"
                                        } else {
                                            Play { class: "w-3.5 h-3.5 text-emerald-400" }
                                            "Start"
                                        }
                                    }
                                }

                                div { class: "flex items-center justify-between",
                                    span { class: "text-sm text-muted-foreground", "Model" }
                                    span { class: "text-sm font-mono", "{config.model}" }
                                }

                                div { class: "flex items-center justify-between gap-3{disabled_class}",
                                    span { class: "text-sm",
                                        "Interval"
                                        if !is_scd30 { span { class: "text-xs text-muted-foreground ml-1", "(fixed)" } }
                                    }
                                    div { class: "flex items-center gap-2",
                                        input {
                                            class: "w-16 px-2 py-1 rounded border border-border bg-background text-foreground text-sm text-center",
                                            r#type: "number",
                                            min: "2",
                                            max: "1800",
                                            value: "{config.measurement_interval_seconds}",
                                            onchange: move |event| {
                                                if let Ok(seconds) = event.value().parse::<u16>() {
                                                    let url = device_url.read().clone();
                                                    spawn(async move {
                                                        let _ = api::set_co2_config(&url, &serde_json::json!({"measurement_interval_seconds": seconds})).await;
                                                        if let Ok(response) = api::fetch_co2_config(&url).await {
                                                            co2_config.set(Some(response.data));
                                                        }
                                                    });
                                                }
                                            },
                                        }
                                        span { class: "text-xs text-muted-foreground", "seconds" }
                                    }
                                }

                                div { class: "flex items-center justify-between{disabled_class}",
                                    span { class: "text-sm", "Auto-calibration (ASC)" }
                                    label { class: "relative inline-flex items-center cursor-pointer",
                                        input {
                                            r#type: "checkbox",
                                            class: "accent-primary",
                                            checked: config.auto_calibration_enabled,
                                            onchange: move |event| {
                                                let enabled = event.checked();
                                                let url = device_url.read().clone();
                                                spawn(async move {
                                                    let _ = api::set_co2_config(&url, &serde_json::json!({"auto_calibration_enabled": enabled})).await;
                                                    if let Ok(response) = api::fetch_co2_config(&url).await {
                                                        co2_config.set(Some(response.data));
                                                    }
                                                });
                                            },
                                        }
                                    }
                                }

                                div { class: "flex items-center justify-between gap-3{disabled_class}",
                                    span { class: "text-sm", "Temp offset" }
                                    div { class: "flex items-center gap-2",
                                        input {
                                            class: "w-16 px-2 py-1 rounded border border-border bg-background text-foreground text-sm text-center",
                                            r#type: "number",
                                            step: "0.1",
                                            min: "0",
                                            max: "50",
                                            value: "{config.temperature_offset_celsius}",
                                            onchange: move |event| {
                                                if let Ok(offset) = event.value().parse::<f64>() {
                                                    let url = device_url.read().clone();
                                                    spawn(async move {
                                                        let _ = api::set_co2_config(&url, &serde_json::json!({"temperature_offset_celsius": offset})).await;
                                                        if let Ok(response) = api::fetch_co2_config(&url).await {
                                                            co2_config.set(Some(response.data));
                                                        }
                                                    });
                                                }
                                            },
                                        }
                                        span { class: "text-xs text-muted-foreground", "°C" }
                                    }
                                }

                                div { class: "flex items-center justify-between gap-3{disabled_class}",
                                    span { class: "text-sm", "Altitude" }
                                    div { class: "flex items-center gap-2",
                                        input {
                                            class: "w-20 px-2 py-1 rounded border border-border bg-background text-foreground text-sm text-center",
                                            r#type: "number",
                                            min: "0",
                                            max: "10000",
                                            value: "{config.altitude_meters}",
                                            onchange: move |event| {
                                                if let Ok(altitude) = event.value().parse::<u16>() {
                                                    let url = device_url.read().clone();
                                                    spawn(async move {
                                                        let _ = api::set_co2_config(&url, &serde_json::json!({"altitude_meters": altitude})).await;
                                                        if let Ok(response) = api::fetch_co2_config(&url).await {
                                                            co2_config.set(Some(response.data));
                                                        }
                                                    });
                                                }
                                            },
                                        }
                                        span { class: "text-xs text-muted-foreground", "m" }
                                    }
                                }

                                div { class: "flex items-center justify-between gap-3{disabled_class}",
                                    span { class: "text-sm", "Force recalibration" }
                                    div { class: "flex items-center gap-2",
                                        input {
                                            id: "frc-ppm-input",
                                            class: "w-20 px-2 py-1 rounded border border-border bg-background text-foreground text-sm text-center",
                                            r#type: "number",
                                            min: "400",
                                            max: "2000",
                                            placeholder: "400",
                                        }
                                        button {
                                            class: "px-3 py-1.5 rounded-lg border border-destructive/50 text-destructive text-xs hover:bg-destructive/10 transition-colors",
                                            onclick: move |_| {
                                                let url = device_url.read().clone();
                                                spawn(async move {
                                                    let js_result = document::eval(
                                                        "document.getElementById('frc-ppm-input')?.value || '400'"
                                                    );
                                                    let ppm_str: String = js_result.await.unwrap_or_default().to_string().replace('"', "");
                                                    let ppm: u16 = ppm_str.parse().unwrap_or(400);
                                                    let _ = api::set_co2_config(&url, &serde_json::json!({"forced_recalibration_ppm": ppm})).await;
                                                    show_toast(format!("Forced recalibration to {ppm} ppm"), "ok");
                                                });
                                            },
                                            "Calibrate"
                                        }
                                        span { class: "text-xs text-muted-foreground", "ppm" }
                                    }
                                }
                                } // rsx!
                                } // let is_scd30 block
                            } else {
                                p { class: "text-sm text-muted-foreground", "Loading config..." }
                            }
                        }
                    }
                }
            }
        }
    }
}
