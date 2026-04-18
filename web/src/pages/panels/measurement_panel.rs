use super::{
    Co2Row, MeasurementState, MeasurementTab, PressureRow, SensorAvailability, Td,
    TemperatureHumidityRow, Th, VoltageRow, build_csv, download_csv, fetch_and_add_sensor_readings,
};
use crate::{api::Co2ConfigData, services::Co2Service};
use dioxus::{prelude::*, signals::ReadSignal};
use dioxus_primitives::{
    tabs::{TabContent, TabList, TabTrigger, Tabs},
    tooltip::{Tooltip, TooltipContent, TooltipTrigger},
};
use lucide_dioxus::{Download, LoaderCircle};
use ui::components::{
    button::{Button, ButtonVariant},
    checkbox::{Checkbox, CheckboxSize},
    input::Input,
    label::Label,
};

fn sample_button(
    mut sampling: Signal<bool>,
    device_url: Signal<String>,
    measurement: Signal<MeasurementState>,
    icon: Element,
) -> Element {
    rsx! {
        Button {
            class: "px-3 py-2 rounded-lg text-foreground flex items-center gap-2 transition-colors hover:bg-muted/70 text-sm".to_string(),
            variant: ButtonVariant::Outline,
            disabled: *sampling.read(),
            on_click: move |_| {
                sampling.set(true);
                let url = device_url.read().clone();
                let measurement = measurement.clone();
                spawn(async move {
                    fetch_and_add_sensor_readings(&url, measurement).await;
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
        Button {
            class: "px-3 py-2 rounded-lg text-foreground flex items-center gap-2 transition-colors hover:bg-muted/70 text-sm".to_string(),
            variant: ButtonVariant::Outline,
            on_click: on_click,
            icon_left: rsx! { Download { class: "w-4 h-4" } },
            "CSV"
        }
    }
}

#[component]
pub fn MeasurementPanel(
    device_url: Signal<String>,
    measurement: Signal<MeasurementState>,
    co2_config: Signal<Option<Co2ConfigData>>,
    sampling: Signal<bool>,
    active_tab: Signal<MeasurementTab>,
) -> Element {
    let avail = *measurement.read().availability.read();

    let has_any_sensor = avail.temperature_humidity || avail.voltage || avail.pressure || avail.co2;

    let default_tab_value = if has_any_sensor {
        if avail.temperature_humidity {
            "temp_humidity"
        } else if avail.voltage {
            "voltage"
        } else if avail.pressure {
            "pressure"
        } else {
            "co2"
        }
    } else {
        "temp_humidity"
    };

    let mut tab_value: Signal<Option<String>> = use_signal(|| None);

    const TABS: [MeasurementTab; 4] = [
        MeasurementTab::TemperatureHumidity,
        MeasurementTab::Voltage,
        MeasurementTab::Pressure,
        MeasurementTab::CarbonDioxide,
    ];

    rsx! {
        section { id: "cloudevents-section", class: "panel-shell-strong p-4",
            Tabs {
                value: ReadSignal::from(tab_value),
                default_value: default_tab_value,
                horizontal: true,
                on_value_change: move |val: String| {
                    active_tab.set(MeasurementTab::from_value(&val));
                },
                TabList {
                    class: "flex w-full border border-border rounded-full p-1 mb-3",
                    if !has_any_sensor {
                        div { class: "w-full py-2 text-center text-muted-foreground", "No sensors connected" }
                    } else {
                        for (idx, tab) in TABS.iter().enumerate() {
                            if tab.is_available(&avail) {
                                div {
                                    class: "flex-1",
                                    onmouseenter: move |_| {
                                        active_tab.set(*tab);
                                        tab_value.set(Some(tab.to_value()));
                                    },
                                    TabTrigger {
                                        value: tab.to_value(),
                                        index: idx,
                                        class: if *active_tab.read() == *tab {
                                            "w-full py-2 text-center rounded-full border border-border bg-background text-foreground font-medium transition-all duration-200"
                                        } else {
                                            "w-full py-2 text-center rounded-full text-muted-foreground hover:text-foreground transition-all duration-200"
                                        },
                                        "{tab.label()}"
                                    }
                                }
                            }
                        }
                    }
                }

                {
                    rsx! {
                        if avail.temperature_humidity {
                            TabContent {
                                value: "temp_humidity".to_string(),
                                index: use_signal(|| 0usize),
                                {thm_panel(device_url, measurement, sampling)}
                            }
                        }
                        if avail.voltage {
                            TabContent {
                                value: "voltage".to_string(),
                                index: use_signal(|| 1usize),
                                {voltage_panel(device_url, measurement, sampling)}
                            }
                        }
                        if avail.pressure {
                            TabContent {
                                value: "pressure".to_string(),
                                index: use_signal(|| 2usize),
                                {pressure_panel(device_url, measurement, sampling)}
                            }
                        }
                        if avail.co2 {
                            TabContent {
                                value: "co2".to_string(),
                                index: use_signal(|| 3usize),
                                {co2_panel(device_url, measurement, co2_config, sampling)}
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
    measurement: Signal<MeasurementState>,
    mut co2_config: Signal<Option<Co2ConfigData>>,
    sampling: Signal<bool>,
) -> Element {
    let co2_readings = measurement.read().co2_readings;
    let asc_checkbox_label = use_signal(|| Some("co2-asc-checkbox".to_string()));

    rsx! {
        div {
            div { class: "flex items-center gap-2 flex-wrap mb-3",
                if let Some(ref config) = *co2_config.read() {
                    span { class: "text-xs font-mono text-muted-foreground border border-border rounded px-1.5 py-0.5", "{config.model}" }

                    Button {
                        variant: ButtonVariant::Outline,
                        class: "text-xs px-1.5 py-0.5 flex items-center gap-1 hover:bg-muted/50".to_string(),
                        on_click: move |_| {
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
                                    Input {
                                        class: Some("w-14 h-auto px-1.5 py-0.5 rounded border border-border bg-background text-foreground text-xs text-center focus:ring-0 focus:ring-offset-0".to_string()),
                                        input_type: "number".to_string(),
                                        min: "2",
                                        max: "1800",
                                        aria_label: Some("Measurement interval (seconds)".to_string()),
                                        value: config.measurement_interval_seconds.to_string(),
                                        on_change: Some(Callback::new(move |e: FormEvent| {
                                            if let Ok(s) = e.value().parse::<u16>() {
                                                let url = device_url.read().clone();
                                                spawn(async move {
                                                    let _ = Co2Service::set_config(&url, &serde_json::json!({"measurement_interval_seconds": s})).await;
                                                    if let Ok(r) = Co2Service::get_config(&url).await { co2_config.set(Some(r.data)); }
                                                });
                                            }
                                        })),
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
                                    Label {
                                        for_id: asc_checkbox_label,
                                        class: Some("mb-0 inline-flex items-center gap-1 text-xs text-muted-foreground cursor-pointer font-normal".to_string()),
                                        {
                                            let mut asc_signal = use_signal(|| config.auto_calibration_enabled);
                                            rsx! {
                                                Checkbox {
                                                    id: Some("co2-asc-checkbox".to_string()),
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
                                    Input {
                                        class: Some("w-12 h-auto px-1.5 py-0.5 rounded border border-border bg-background text-foreground text-xs text-center focus:ring-0 focus:ring-offset-0".to_string()),
                                        input_type: "number".to_string(),
                                        step: "0.1",
                                        min: "0",
                                        max: "50",
                                        aria_label: Some("Temperature offset (°C)".to_string()),
                                        value: config.temperature_offset_celsius.to_string(),
                                        on_change: Some(Callback::new(move |e: FormEvent| {
                                            if let Ok(offset) = e.value().parse::<f64>() {
                                                let url = device_url.read().clone();
                                                spawn(async move {
                                                    let _ = Co2Service::set_config(&url, &serde_json::json!({"temperature_offset_celsius": offset})).await;
                                                    if let Ok(r) = Co2Service::get_config(&url).await { co2_config.set(Some(r.data)); }
                                                });
                                            }
                                        })),
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
                                    Input {
                                        class: Some("w-14 h-auto px-1.5 py-0.5 rounded border border-border bg-background text-foreground text-xs text-center focus:ring-0 focus:ring-offset-0".to_string()),
                                        input_type: "number".to_string(),
                                        min: "0",
                                        max: "10000",
                                        aria_label: Some("Altitude compensation (m)".to_string()),
                                        value: config.altitude_meters.to_string(),
                                        on_change: Some(Callback::new(move |e: FormEvent| {
                                            if let Ok(alt) = e.value().parse::<u16>() {
                                                let url = device_url.read().clone();
                                                spawn(async move {
                                                    let _ = Co2Service::set_config(&url, &serde_json::json!({"altitude_meters": alt})).await;
                                                    if let Ok(r) = Co2Service::get_config(&url).await { co2_config.set(Some(r.data)); }
                                                });
                                            }
                                        })),
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
                        download_csv("co2_readings.csv", &build_csv(&co2_readings.read()));
                    })}
                }

                {sample_button(sampling, device_url, measurement,
                    rsx! { lucide_dioxus::FlaskConical { class: "w-4 h-4" } })}
            }

            div { class: "border border-border rounded-lg overflow-scroll min-h-[320px] max-h-[460px]",
                div { class: "w-full overflow-auto h-full",
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
    measurement: Signal<MeasurementState>,
    sampling: Signal<bool>,
) -> Element {
    let temperature_humidity_readings = measurement.read().temperature_humidity_readings;
    rsx! {
        div {
            div { class: "flex items-center gap-2 flex-wrap mb-3",
                if let Some(ref row) = temperature_humidity_readings.read().last() {
                    if !row.default_model.is_empty() {
                        span { class: "text-xs font-mono text-muted-foreground border border-border rounded px-1.5 py-0.5", "{row.default_model}" }
                    }
                }
                div { class: "flex-1" }

                if !temperature_humidity_readings.read().is_empty() {
                    {csv_button(move |_| {
                        download_csv("temperature_humidity.csv", &build_csv(&temperature_humidity_readings.read()));
                    })}
                }

                {sample_button(sampling, device_url, measurement,
                    rsx! { lucide_dioxus::Thermometer { class: "w-4 h-4" } })}
            }

            div { class: "border border-border rounded-lg overflow-scroll min-h-[320px] max-h-[460px]",
                div { class: "w-full overflow-auto h-full",
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

fn pressure_panel(
    device_url: Signal<String>,
    measurement: Signal<MeasurementState>,
    sampling: Signal<bool>,
) -> Element {
    let pressure_readings = measurement.read().pressure_readings;
    rsx! {
        div {
            div { class: "flex items-center gap-2 flex-wrap mb-3",
                if let Some(ref row) = pressure_readings.read().last() {
                    span { class: "text-xs font-mono text-muted-foreground border border-border rounded px-1.5 py-0.5", "{row.model}" }
                }
                div { class: "flex-1" }

                if !pressure_readings.read().is_empty() {
                    {csv_button(move |_| {
                        download_csv("pressure.csv", &build_csv(&pressure_readings.read()));
                    })}
                }

                {sample_button(sampling, device_url, measurement,
                    rsx! { lucide_dioxus::Gauge { class: "w-4 h-4" } })}
            }

            div { class: "border border-border rounded-lg overflow-scroll min-h-[320px] max-h-[460px]",
                div { class: "w-full overflow-auto h-full",
                    table { class: "min-w-full border-collapse",
                        thead { class: "bg-muted",
                            tr {
                                Th { "#" }
                                Th { "Pressure (hPa)" }
                                Th { "Temp (\u{00b0}C)" }
                                Th { "TIME" }
                            }
                        }
                        tbody {
                            if pressure_readings.read().is_empty() {
                                tr {
                                    td { colspan: "4", class: "px-4 py-10 text-center",
                                        div { class: "flex flex-col items-center gap-2",
                                            lucide_dioxus::Gauge { class: "w-9 h-9 text-muted-foreground" }
                                            h3 { class: "text-sm font-medium text-foreground", "No readings yet" }
                                            p { class: "text-sm text-muted-foreground", "Data streams automatically every 5 seconds" }
                                        }
                                    }
                                }
                            }
                            for row in pressure_readings.read().iter().rev() {
                                tr { key: "{row.row}", class: "border-b border-border hover:bg-muted/40 transition-colors",
                                    Td { "{row.row}" }
                                    Td { class: "tabular-nums", "{row.pressure_hpa:.2}" }
                                    Td { class: "tabular-nums", "{row.temperature_celsius:.1}" }
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
    measurement: Signal<MeasurementState>,
    sampling: Signal<bool>,
) -> Element {
    let voltage_readings = measurement.read().voltage_readings;
    rsx! {
        div {
            div { class: "flex items-center gap-2 flex-wrap mb-3",
                if let Some(ref row) = voltage_readings.read().last() {
                    if !row.gain.is_empty() {
                        span { class: "text-xs font-mono text-muted-foreground border border-border rounded px-1.5 py-0.5", "{row.gain}" }
                    }
                }
                div { class: "flex-1" }

                if !voltage_readings.read().is_empty() {
                    {csv_button(move |_| {
                        download_csv("voltage.csv", &build_csv(&voltage_readings.read()));
                    })}
                }

                {sample_button(sampling, device_url, measurement,
                    rsx! { lucide_dioxus::Zap { class: "w-4 h-4" } })}
            }

            div { class: "border border-border rounded-lg overflow-scroll min-h-[320px] max-h-[460px]",
                div { class: "w-full overflow-auto h-full",
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
