use super::{
    build_co2_csv, build_temperature_humidity_csv, build_voltage_csv, download_csv,
    fetch_and_add_sensor_readings, Co2Row, MeasurementTab, Td, TemperatureHumidityRow,
    Th, VoltageRow, ENABLE_CO2, ENABLE_CURRENT, ENABLE_TEMPERATURE_HUMIDITY, ENABLE_VOLTAGE,
};
use crate::api::Co2ConfigData;
use crate::services::Co2Service;
use dioxus::prelude::*;
use dioxus::signals::ReadSignal;
use dioxus_primitives::tabs::{TabContent, TabList, TabTrigger, Tabs};
use dioxus_primitives::tooltip::{Tooltip, TooltipContent, TooltipTrigger};
use lucide_dioxus::{Download, LoaderCircle};
use ui::components::checkbox::{Checkbox, CheckboxSize};

fn sample_button(
    mut sampling: Signal<bool>,
    device_url: Signal<String>,
    last_event_time: Signal<String>,
    co2_readings: Signal<Vec<Co2Row>>,
    temperature_humidity_readings: Signal<Vec<TemperatureHumidityRow>>,
    voltage_readings: Signal<Vec<VoltageRow>>,
    icon: Element,
) -> Element {
    rsx! {
        button {
            class: "px-4 py-2 rounded-lg bg-accent text-accent-foreground flex items-center gap-2 transition-colors hover:bg-accent/85",
            disabled: *sampling.read(),
            onclick: move |_| {
                sampling.set(true);
                let url = device_url.read().clone();
                spawn(async move {
                    fetch_and_add_sensor_readings(
                        &url, last_event_time, co2_readings, temperature_humidity_readings, voltage_readings,
                    ).await;
                    sampling.set(false);
                });
            },
            if *sampling.read() {
                LoaderCircle { class: "w-4 h-4 animate-spin" }
                "Sampling..."
            } else {
                {icon}
                "Sample"
                span { class: "text-xs text-muted-foreground bg-muted px-1.5 py-0.5 rounded", "C+\u{21b5}" }
            }
        }
    }
}

fn csv_button(on_click: impl FnMut(dioxus::events::MouseEvent) + 'static) -> Element {
    rsx! {
        button {
            class: "px-3 py-2 rounded-lg border border-border text-foreground flex items-center gap-2 transition-colors hover:bg-muted/70 text-sm",
            onclick: on_click,
            Download { class: "w-4 h-4" }
            "CSV"
        }
    }
}

#[component]
pub fn MeasurementPanel(
    device_url: Signal<String>,
    last_event_time: Signal<String>,
    co2_readings: Signal<Vec<Co2Row>>,
    temperature_humidity_readings: Signal<Vec<TemperatureHumidityRow>>,
    voltage_readings: Signal<Vec<VoltageRow>>,
    co2_config: Signal<Option<Co2ConfigData>>,
    sampling: Signal<bool>,
    active_tab: Signal<MeasurementTab>,
) -> Element {
    let default_tab = active_tab.read().to_value();
    let mut tab_value: Signal<Option<String>> = use_signal(|| None);

    let mut tab_index = 0usize;

    rsx! {
        section { id: "cloudevents-section", class: "panel-shell-strong p-4",
            Tabs {
                value: ReadSignal::from(tab_value),
                default_value: default_tab,
                horizontal: true,
                on_value_change: move |val: String| {
                    active_tab.set(MeasurementTab::from_value(&val));
                },
                TabList {
                    class: "flex w-full border border-border rounded-full p-1 mb-4",
                    {
                        let mut idx = 0usize;
                        let triggers = rsx! {
                            if ENABLE_TEMPERATURE_HUMIDITY {
                                div {
                                    class: "flex-1",
                                    onmouseenter: move |_| { active_tab.set(MeasurementTab::TemperatureHumidity); tab_value.set(Some("temp_humidity".into())); },
                                    TabTrigger {
                                        value: "temp_humidity".to_string(),
                                        index: idx,
                                        class: if *active_tab.read() == MeasurementTab::TemperatureHumidity {
                                            "w-full py-2 text-center rounded-full border border-border bg-background text-foreground font-medium transition-all duration-200"
                                        } else {
                                            "w-full py-2 text-center rounded-full text-muted-foreground hover:text-foreground transition-all duration-200"
                                        },
                                        "Temp/Humidity"
                                    }
                                }
                                { idx += 1; rsx! {} }
                            }
                            if ENABLE_VOLTAGE {
                                div {
                                    class: "flex-1",
                                    onmouseenter: move |_| { active_tab.set(MeasurementTab::Voltage); tab_value.set(Some("voltage".into())); },
                                    TabTrigger {
                                        value: "voltage".to_string(),
                                        index: idx,
                                        class: if *active_tab.read() == MeasurementTab::Voltage {
                                            "w-full py-2 text-center rounded-full border border-border bg-background text-foreground font-medium transition-all duration-200"
                                        } else {
                                            "w-full py-2 text-center rounded-full text-muted-foreground hover:text-foreground transition-all duration-200"
                                        },
                                        "Voltage"
                                    }
                                }
                                { idx += 1; rsx! {} }
                            }
                            if ENABLE_CURRENT {
                                div {
                                    class: "flex-1",
                                    onmouseenter: move |_| { active_tab.set(MeasurementTab::Current); tab_value.set(Some("current".into())); },
                                    TabTrigger {
                                        value: "current".to_string(),
                                        index: idx,
                                        class: if *active_tab.read() == MeasurementTab::Current {
                                            "w-full py-2 text-center rounded-full border border-border bg-background text-foreground font-medium transition-all duration-200"
                                        } else {
                                            "w-full py-2 text-center rounded-full text-muted-foreground hover:text-foreground transition-all duration-200"
                                        },
                                        "Current"
                                    }
                                }
                                { idx += 1; rsx! {} }
                            }
                            if ENABLE_CO2 {
                                div {
                                    class: "flex-1",
                                    onmouseenter: move |_| { active_tab.set(MeasurementTab::CarbonDioxide); tab_value.set(Some("co2".into())); },
                                    TabTrigger {
                                        value: "co2".to_string(),
                                        index: idx,
                                        class: if *active_tab.read() == MeasurementTab::CarbonDioxide {
                                            "w-full py-2 text-center rounded-full border border-border bg-background text-foreground font-medium transition-all duration-200"
                                        } else {
                                            "w-full py-2 text-center rounded-full text-muted-foreground hover:text-foreground transition-all duration-200"
                                        },
                                        "CO\u{2082}"
                                    }
                                }
                            }
                        };
                        tab_index = idx;
                        triggers
                    }
                }

                {
                    let mut content_idx = 0usize;
                    rsx! {
                        if ENABLE_TEMPERATURE_HUMIDITY {
                            TabContent {
                                value: "temp_humidity".to_string(),
                                index: content_idx,
                                {thm_panel(device_url, last_event_time, co2_readings, temperature_humidity_readings, voltage_readings, sampling)}
                            }
                            { content_idx += 1; rsx! {} }
                        }
                        if ENABLE_VOLTAGE {
                            TabContent {
                                value: "voltage".to_string(),
                                index: content_idx,
                                {voltage_panel(device_url, last_event_time, co2_readings, temperature_humidity_readings, voltage_readings, sampling)}
                            }
                            { content_idx += 1; rsx! {} }
                        }
                        if ENABLE_CURRENT {
                            TabContent {
                                value: "current".to_string(),
                                index: content_idx,
                            }
                            { content_idx += 1; rsx! {} }
                        }
                        if ENABLE_CO2 {
                            TabContent {
                                value: "co2".to_string(),
                                index: content_idx,
                                {co2_panel(device_url, last_event_time, co2_readings, temperature_humidity_readings, voltage_readings, co2_config, sampling)}
                            }
                        }
                    }
                }
            }
        }
    }
}

fn co2_panel(
    device_url: Signal<String>,
    last_event_time: Signal<String>,
    co2_readings: Signal<Vec<Co2Row>>,
    temperature_humidity_readings: Signal<Vec<TemperatureHumidityRow>>,
    voltage_readings: Signal<Vec<VoltageRow>>,
    mut co2_config: Signal<Option<Co2ConfigData>>,
    sampling: Signal<bool>,
) -> Element {
    rsx! {
        div {
            div { class: "flex items-center gap-2 flex-wrap mb-3",
                if let Some(ref config) = *co2_config.read() {
                    span { class: "text-xs font-mono text-muted-foreground border border-border rounded px-1.5 py-0.5", "{config.model}" }

                    button {
                        class: "text-xs border border-border rounded px-1.5 py-0.5 flex items-center gap-1 transition-colors hover:bg-muted/50",
                        onclick: move |_| {
                            let url = device_url.read().clone();
                            let is_measuring = co2_config.read().as_ref().map(|c| c.measuring).unwrap_or(false);
                            spawn(async move {
                                if is_measuring { let _ = Co2Service::stop(&url).await; }
                                else { let _ = Co2Service::start(&url).await; }
                                if let Ok(r) = Co2Service::get_config(&url).await { co2_config.set(Some(r.data)); }
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

                    if config.model == "SCD30" {
                        div { class: "hidden sm:flex items-center gap-2",
                            Tooltip {
                                TooltipTrigger {
                                    input {
                                        class: "w-14 px-1.5 py-0.5 rounded border border-border bg-background text-foreground text-xs text-center",
                                        r#type: "number", min: "2", max: "1800",
                                        aria_label: "Measurement interval (seconds)",
                                        value: "{config.measurement_interval_seconds}",
                                        onchange: move |e| {
                                            if let Ok(s) = e.value().parse::<u16>() {
                                                let url = device_url.read().clone();
                                                spawn(async move {
                                                    let _ = Co2Service::set_config(&url, &serde_json::json!({"measurement_interval_seconds": s})).await;
                                                    if let Ok(r) = Co2Service::get_config(&url).await { co2_config.set(Some(r.data)); }
                                                });
                                            }
                                        },
                                    }
                                }
                                TooltipContent {
                                    class: "z-50 px-2 py-1 text-xs rounded bg-popover text-popover-foreground border border-border shadow",
                                    "Measurement interval (seconds)"
                                }
                            }
                            span { class: "text-xs text-muted-foreground", "s" }
                            Tooltip {
                                TooltipTrigger {
                                    label { class: "flex items-center gap-1 text-xs text-muted-foreground cursor-pointer",
                                        {
                                            let mut asc_signal = use_signal(|| config.auto_calibration_enabled);
                                            rsx! {
                                                Checkbox {
                                                    checked: asc_signal,
                                                    size: CheckboxSize::Small,
                                                    aria_label: "Auto-calibration (ASC)",
                                                    on_checked_change: move |enabled: bool| {
                                                        asc_signal.set(enabled);
                                                        let url = device_url.read().clone();
                                                        spawn(async move {
                                                            let _ = Co2Service::set_config(&url, &serde_json::json!({"auto_calibration_enabled": enabled})).await;
                                                            if let Ok(r) = Co2Service::get_config(&url).await { co2_config.set(Some(r.data)); }
                                                        });
                                                    },
                                                }
                                            }
                                        }
                                        "ASC"
                                    }
                                }
                                TooltipContent {
                                    class: "z-50 px-2 py-1 text-xs rounded bg-popover text-popover-foreground border border-border shadow",
                                    "Auto-calibration (ASC)"
                                }
                            }
                            Tooltip {
                                TooltipTrigger {
                                    input {
                                        class: "w-12 px-1.5 py-0.5 rounded border border-border bg-background text-foreground text-xs text-center",
                                        r#type: "number", step: "0.1", min: "0", max: "50",
                                        aria_label: "Temperature offset (\u{00b0}C)",
                                        value: "{config.temperature_offset_celsius}",
                                        onchange: move |e| {
                                            if let Ok(offset) = e.value().parse::<f64>() {
                                                let url = device_url.read().clone();
                                                spawn(async move {
                                                    let _ = Co2Service::set_config(&url, &serde_json::json!({"temperature_offset_celsius": offset})).await;
                                                    if let Ok(r) = Co2Service::get_config(&url).await { co2_config.set(Some(r.data)); }
                                                });
                                            }
                                        },
                                    }
                                }
                                TooltipContent {
                                    class: "z-50 px-2 py-1 text-xs rounded bg-popover text-popover-foreground border border-border shadow",
                                    "Temperature offset (\u{00b0}C)"
                                }
                            }
                            span { class: "text-xs text-muted-foreground", "\u{00b0}C" }
                            Tooltip {
                                TooltipTrigger {
                                    input {
                                        class: "w-14 px-1.5 py-0.5 rounded border border-border bg-background text-foreground text-xs text-center",
                                        r#type: "number", min: "0", max: "10000",
                                        aria_label: "Altitude compensation (m)",
                                        value: "{config.altitude_meters}",
                                        onchange: move |e| {
                                            if let Ok(alt) = e.value().parse::<u16>() {
                                                let url = device_url.read().clone();
                                                spawn(async move {
                                                    let _ = Co2Service::set_config(&url, &serde_json::json!({"altitude_meters": alt})).await;
                                                    if let Ok(r) = Co2Service::get_config(&url).await { co2_config.set(Some(r.data)); }
                                                });
                                            }
                                        },
                                    }
                                }
                                TooltipContent {
                                    class: "z-50 px-2 py-1 text-xs rounded bg-popover text-popover-foreground border border-border shadow",
                                    "Altitude compensation (m)"
                                }
                            }
                            span { class: "text-xs text-muted-foreground", "m" }
                        }
                    }
                } else {
                    span { class: "text-xs text-muted-foreground", "(polling every 5s)" }
                }

                div { class: "flex-1" }

                if !co2_readings.read().is_empty() {
                    {csv_button(move |_| {
                        download_csv("co2_readings.csv", &build_co2_csv(&co2_readings.read()));
                    })}
                }

                {sample_button(sampling, device_url, last_event_time, co2_readings, temperature_humidity_readings, voltage_readings,
                    rsx! { lucide_dioxus::FlaskConical { class: "w-4 h-4" } })}
            }

            div { class: "border border-border rounded-lg overflow-hidden",
                div { class: "w-full overflow-auto h-[400px]",
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
                                tr { key: "{row.row}", class: "border-b border-border hover:bg-muted/40 transition-colors",
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
}

fn thm_panel(
    device_url: Signal<String>,
    last_event_time: Signal<String>,
    co2_readings: Signal<Vec<Co2Row>>,
    temperature_humidity_readings: Signal<Vec<TemperatureHumidityRow>>,
    voltage_readings: Signal<Vec<VoltageRow>>,
    sampling: Signal<bool>,
) -> Element {
    rsx! {
        div {
            div { class: "flex items-center gap-2 flex-wrap mb-3",
                span { class: "text-xs font-mono text-muted-foreground border border-border rounded px-1.5 py-0.5", "CHT832X" }
                div { class: "flex-1" }

                if !temperature_humidity_readings.read().is_empty() {
                    {csv_button(move |_| {
                        download_csv("temperature_humidity.csv", &build_temperature_humidity_csv(&temperature_humidity_readings.read()));
                    })}
                }

                {sample_button(sampling, device_url, last_event_time, co2_readings, temperature_humidity_readings, voltage_readings,
                    rsx! { lucide_dioxus::Thermometer { class: "w-4 h-4" } })}
            }

            div { class: "border border-border rounded-lg overflow-hidden",
                div { class: "w-full overflow-auto h-[400px]",
                    table { class: "min-w-full border-collapse",
                        thead { class: "bg-muted",
                            tr {
                                Th { "#" }
                                {
                                    let count = temperature_humidity_readings.read()
                                        .first().map(|r| r.sensors.len()).unwrap_or(0);
                                    (0..count).map(|i| rsx! {
                                        Th { "\u{00b0}C {i}" }
                                        Th { "% {i}" }
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
                                tr { key: "{row.row}", class: "border-b border-border hover:bg-muted/40 transition-colors",
                                    Td { "{row.row}" }
                                    for sensor in row.sensors.iter() {
                                        if sensor.read_ok {
                                            Td { class: "tabular-nums", "{sensor.temperature_celsius:.1}" }
                                            Td { class: "tabular-nums", "{sensor.relative_humidity_percent:.1}" }
                                        } else {
                                            Td { class: "text-muted-foreground", "\u{2014}" }
                                            Td { class: "text-muted-foreground", "\u{2014}" }
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
}

fn voltage_panel(
    device_url: Signal<String>,
    last_event_time: Signal<String>,
    co2_readings: Signal<Vec<Co2Row>>,
    temperature_humidity_readings: Signal<Vec<TemperatureHumidityRow>>,
    voltage_readings: Signal<Vec<VoltageRow>>,
    sampling: Signal<bool>,
) -> Element {
    rsx! {
        div {
            div { class: "flex items-center gap-2 flex-wrap mb-3",
                span { class: "text-xs font-mono text-muted-foreground border border-border rounded px-1.5 py-0.5", "ADS1115" }
                if let Some(ref row) = voltage_readings.read().last() {
                    span { class: "text-xs font-mono text-muted-foreground border border-border rounded px-1.5 py-0.5", "{row.gain}" }
                }
                div { class: "flex-1" }

                if !voltage_readings.read().is_empty() {
                    {csv_button(move |_| {
                        download_csv("voltage.csv", &build_voltage_csv(&voltage_readings.read()));
                    })}
                }

                {sample_button(sampling, device_url, last_event_time, co2_readings, temperature_humidity_readings, voltage_readings,
                    rsx! { lucide_dioxus::Zap { class: "w-4 h-4" } })}
            }

            div { class: "border border-border rounded-lg overflow-hidden",
                div { class: "w-full overflow-auto h-[400px]",
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
                                tr { key: "{row.row}", class: "border-b border-border hover:bg-muted/40 transition-colors",
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
