use super::{
    Co2Row, CurrentRow, MeasurementState, MeasurementTab, PressureRow, RainfallRow,
    SensorAvailability, SoilRow, SolarRadiationRow, Td, TemperatureHumidityRow, Th, VoltageRow,
    WindDirectionRow, WindSpeedRow, build_csv, download_csv, fetch_and_add_sensor_readings,
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

    let has_any_sensor = avail.temperature_humidity || avail.voltage || avail.current
        || avail.pressure || avail.co2 || avail.rainfall || avail.soil
        || avail.wind_speed || avail.wind_direction || avail.solar_radiation;

    let default_tab_value = if has_any_sensor {
        if avail.temperature_humidity {
            "temp_humidity"
        } else if avail.voltage {
            "voltage"
        } else if avail.current {
            "current"
        } else if avail.pressure {
            "pressure"
        } else if avail.co2 {
            "co2"
        } else if avail.rainfall {
            "rainfall"
        } else if avail.soil {
            "soil"
        } else if avail.wind_speed {
            "wind_speed"
        } else if avail.wind_direction {
            "wind_direction"
        } else {
            "solar_radiation"
        }
    } else {
        "temp_humidity"
    };

    let mut tab_value: Signal<Option<String>> = use_signal(|| None);

    const TABS: [MeasurementTab; 10] = [
        MeasurementTab::TemperatureHumidity,
        MeasurementTab::Voltage,
        MeasurementTab::Current,
        MeasurementTab::Pressure,
        MeasurementTab::CarbonDioxide,
        MeasurementTab::Rainfall,
        MeasurementTab::Soil,
        MeasurementTab::WindSpeed,
        MeasurementTab::WindDirection,
        MeasurementTab::SolarRadiation,
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
                        if avail.rainfall {
                            TabContent {
                                value: "rainfall".to_string(),
                                index: use_signal(|| 4usize),
                                {rainfall_panel(device_url, measurement, sampling)}
                            }
                        }
                        if avail.soil {
                            TabContent {
                                value: "soil".to_string(),
                                index: use_signal(|| 5usize),
                                {soil_panel(device_url, measurement, sampling)}
                            }
                        }
                        if avail.wind_speed {
                            TabContent {
                                value: "wind_speed".to_string(),
                                index: use_signal(|| 6usize),
                                {wind_speed_panel(device_url, measurement, sampling)}
                            }
                        }
                        if avail.wind_direction {
                            TabContent {
                                value: "wind_direction".to_string(),
                                index: use_signal(|| 7usize),
                                {wind_direction_panel(device_url, measurement, sampling)}
                            }
                        }
                        if avail.solar_radiation {
                            TabContent {
                                value: "solar_radiation".to_string(),
                                index: use_signal(|| 8usize),
                                {solar_radiation_panel(device_url, measurement, sampling)}
                            }
                        }
                        if avail.current {
                            TabContent {
                                value: "current".to_string(),
                                index: use_signal(|| 9usize),
                                {current_panel(device_url, measurement, sampling)}
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
                                Th { "CH0 (\u{00B0}C)" }
                                Th { "CH1 (V)" }
                                Th { "CH1 (\u{00B0}C)" }
                                Th { "CH2 (V)" }
                                Th { "CH2 (\u{00B0}C)" }
                                Th { "CH3 (V)" }
                                Th { "CH3 (\u{00B0}C)" }
                                Th { "TIME" }
                            }
                        }
                        tbody {
                            if voltage_readings.read().is_empty() {
                                tr {
                                    td { colspan: "10", class: "px-4 py-10 text-center",
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
                                    for (voltage, temperature) in row.channels.iter().zip(row.temperatures.iter()) {
                                        Td { class: "tabular-nums", "{voltage:.4}" }
                                        Td { class: "tabular-nums", "{temperature:.6}" }
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

fn rainfall_panel(
    device_url: Signal<String>,
    measurement: Signal<MeasurementState>,
    sampling: Signal<bool>,
) -> Element {
    let rainfall_readings = measurement.read().rainfall_readings;
    rsx! {
        div {
            div { class: "flex items-center gap-2 flex-wrap mb-3",
                div { class: "flex-1" }

                if !rainfall_readings.read().is_empty() {
                    {csv_button(move |_| {
                        download_csv("rainfall.csv", &build_csv(&rainfall_readings.read()));
                    })}
                }

                {sample_button(sampling, device_url, measurement,
                    rsx! { lucide_dioxus::CloudRain { class: "w-4 h-4" } })}
            }

            div { class: "border border-border rounded-lg overflow-scroll min-h-[320px] max-h-[460px]",
                div { class: "w-full overflow-auto h-full",
                    table { class: "min-w-full border-collapse",
                        thead { class: "bg-muted",
                            tr {
                                Th { "#" }
                                Th { "Rainfall (mm)" }
                                Th { "TIME" }
                            }
                        }
                        tbody {
                            if rainfall_readings.read().is_empty() {
                                tr {
                                    td { colspan: "3", class: "px-4 py-10 text-center",
                                        div { class: "flex flex-col items-center gap-2",
                                            lucide_dioxus::CloudRain { class: "w-9 h-9 text-muted-foreground" }
                                            h3 { class: "text-sm font-medium text-foreground", "No readings yet" }
                                            p { class: "text-sm text-muted-foreground", "Data streams automatically every 5 seconds" }
                                        }
                                    }
                                }
                            }
                            for row in rainfall_readings.read().iter().rev() {
                                tr { key: "{row.row}", class: "border-b border-border hover:bg-muted/40 transition-colors",
                                    Td { "{row.row}" }
                                    Td { class: "tabular-nums", "{row.rainfall_millimeters:.1}" }
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

fn wind_speed_panel(
    device_url: Signal<String>,
    measurement: Signal<MeasurementState>,
    sampling: Signal<bool>,
) -> Element {
    let wind_speed_readings = measurement.read().wind_speed_readings;
    rsx! {
        div {
            div { class: "flex items-center gap-2 flex-wrap mb-3",
                div { class: "flex-1" }

                if !wind_speed_readings.read().is_empty() {
                    {csv_button(move |_| {
                        download_csv("wind_speed.csv", &build_csv(&wind_speed_readings.read()));
                    })}
                }

                {sample_button(sampling, device_url, measurement,
                    rsx! { lucide_dioxus::Wind { class: "w-4 h-4" } })}
            }

            div { class: "border border-border rounded-lg overflow-scroll min-h-[320px] max-h-[460px]",
                div { class: "w-full overflow-auto h-full",
                    table { class: "min-w-full border-collapse",
                        thead { class: "bg-muted",
                            tr {
                                Th { "#" }
                                Th { "Speed (km/h)" }
                                Th { "TIME" }
                            }
                        }
                        tbody {
                            if wind_speed_readings.read().is_empty() {
                                tr {
                                    td { colspan: "3", class: "px-4 py-10 text-center",
                                        div { class: "flex flex-col items-center gap-2",
                                            lucide_dioxus::Wind { class: "w-9 h-9 text-muted-foreground" }
                                            h3 { class: "text-sm font-medium text-foreground", "No readings yet" }
                                            p { class: "text-sm text-muted-foreground", "Data streams automatically every 5 seconds" }
                                        }
                                    }
                                }
                            }
                            for row in wind_speed_readings.read().iter().rev() {
                                tr { key: "{row.row}", class: "border-b border-border hover:bg-muted/40 transition-colors",
                                    Td { "{row.row}" }
                                    Td { class: "tabular-nums", "{row.kilometers_per_hour:.1}" }
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

fn wind_direction_panel(
    device_url: Signal<String>,
    measurement: Signal<MeasurementState>,
    sampling: Signal<bool>,
) -> Element {
    let wind_direction_readings = measurement.read().wind_direction_readings;
    rsx! {
        div {
            div { class: "flex items-center gap-2 flex-wrap mb-3",
                div { class: "flex-1" }

                if !wind_direction_readings.read().is_empty() {
                    {csv_button(move |_| {
                        download_csv("wind_direction.csv", &build_csv(&wind_direction_readings.read()));
                    })}
                }

                {sample_button(sampling, device_url, measurement,
                    rsx! { lucide_dioxus::Compass { class: "w-4 h-4" } })}
            }

            div { class: "border border-border rounded-lg overflow-scroll min-h-[320px] max-h-[460px]",
                div { class: "w-full overflow-auto h-full",
                    table { class: "min-w-full border-collapse",
                        thead { class: "bg-muted",
                            tr {
                                Th { "#" }
                                Th { "Degrees (\u{00b0})" }
                                Th { "Slice" }
                                Th { "TIME" }
                            }
                        }
                        tbody {
                            if wind_direction_readings.read().is_empty() {
                                tr {
                                    td { colspan: "4", class: "px-4 py-10 text-center",
                                        div { class: "flex flex-col items-center gap-2",
                                            lucide_dioxus::Compass { class: "w-9 h-9 text-muted-foreground" }
                                            h3 { class: "text-sm font-medium text-foreground", "No readings yet" }
                                            p { class: "text-sm text-muted-foreground", "Data streams automatically every 5 seconds" }
                                        }
                                    }
                                }
                            }
                            for row in wind_direction_readings.read().iter().rev() {
                                tr { key: "{row.row}", class: "border-b border-border hover:bg-muted/40 transition-colors",
                                    Td { "{row.row}" }
                                    Td { class: "tabular-nums", "{row.degrees:.1}" }
                                    Td { class: "tabular-nums", "{row.angle_slice}" }
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

fn solar_radiation_panel(
    device_url: Signal<String>,
    measurement: Signal<MeasurementState>,
    sampling: Signal<bool>,
) -> Element {
    let solar_radiation_readings = measurement.read().solar_radiation_readings;
    rsx! {
        div {
            div { class: "flex items-center gap-2 flex-wrap mb-3",
                div { class: "flex-1" }

                if !solar_radiation_readings.read().is_empty() {
                    {csv_button(move |_| {
                        download_csv("solar_radiation.csv", &build_csv(&solar_radiation_readings.read()));
                    })}
                }

                {sample_button(sampling, device_url, measurement,
                    rsx! { lucide_dioxus::Sun { class: "w-4 h-4" } })}
            }

            div { class: "border border-border rounded-lg overflow-scroll min-h-[320px] max-h-[460px]",
                div { class: "w-full overflow-auto h-full",
                    table { class: "min-w-full border-collapse",
                        thead { class: "bg-muted",
                            tr {
                                Th { "#" }
                                Th { "Irradiance (W/m\u{00b2})" }
                                Th { "TIME" }
                            }
                        }
                        tbody {
                            if solar_radiation_readings.read().is_empty() {
                                tr {
                                    td { colspan: "3", class: "px-4 py-10 text-center",
                                        div { class: "flex flex-col items-center gap-2",
                                            lucide_dioxus::Sun { class: "w-9 h-9 text-muted-foreground" }
                                            h3 { class: "text-sm font-medium text-foreground", "No readings yet" }
                                            p { class: "text-sm text-muted-foreground", "Data streams automatically every 5 seconds" }
                                        }
                                    }
                                }
                            }
                            for row in solar_radiation_readings.read().iter().rev() {
                                tr { key: "{row.row}", class: "border-b border-border hover:bg-muted/40 transition-colors",
                                    Td { "{row.row}" }
                                    Td { class: "tabular-nums", "{row.watts_per_square_meter}" }
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

fn current_panel(
    device_url: Signal<String>,
    measurement: Signal<MeasurementState>,
    sampling: Signal<bool>,
) -> Element {
    let current_readings = measurement.read().current_readings;
    rsx! {
        div {
            div { class: "flex items-center gap-2 flex-wrap mb-3",
                div { class: "flex-1" }

                if !current_readings.read().is_empty() {
                    {csv_button(move |_| {
                        download_csv("current.csv", &build_csv(&current_readings.read()));
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
                                Th { "Current (mA)" }
                                Th { "Bus (V)" }
                                Th { "Shunt (mV)" }
                                Th { "Power (mW)" }
                                Th { "Die Temp (\u{00b0}C)" }
                                Th { "TIME" }
                            }
                        }
                        tbody {
                            if current_readings.read().is_empty() {
                                tr {
                                    td { colspan: "7", class: "px-4 py-10 text-center",
                                        div { class: "flex flex-col items-center gap-2",
                                            lucide_dioxus::Zap { class: "w-9 h-9 text-muted-foreground" }
                                            h3 { class: "text-sm font-medium text-foreground", "No readings yet" }
                                            p { class: "text-sm text-muted-foreground", "Data streams automatically every 5 seconds" }
                                        }
                                    }
                                }
                            }
                            for row in current_readings.read().iter().rev() {
                                tr { key: "{row.row}", class: "border-b border-border hover:bg-muted/40 transition-colors",
                                    Td { "{row.row}" }
                                    Td { class: "tabular-nums", "{row.current_milliamps:.3}" }
                                    Td { class: "tabular-nums", "{row.bus_voltage:.4}" }
                                    Td { class: "tabular-nums", "{row.shunt_voltage_millivolts:.4}" }
                                    Td { class: "tabular-nums", "{row.power_milliwatts:.3}" }
                                    Td { class: "tabular-nums", "{row.die_temperature_celsius:.1}" }
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

fn soil_panel(
    device_url: Signal<String>,
    measurement: Signal<MeasurementState>,
    sampling: Signal<bool>,
) -> Element {
    let soil_readings = measurement.read().soil_readings;
    rsx! {
        div {
            div { class: "flex items-center gap-2 flex-wrap mb-3",
                div { class: "flex-1" }

                if !soil_readings.read().is_empty() {
                    {csv_button(move |_| {
                        download_csv("soil.csv", &build_csv(&soil_readings.read()));
                    })}
                }

                {sample_button(sampling, device_url, measurement,
                    rsx! { lucide_dioxus::Sprout { class: "w-4 h-4" } })}
            }

            div { class: "border border-border rounded-lg overflow-scroll min-h-[320px] max-h-[460px]",
                div { class: "w-full overflow-auto h-full",
                    table { class: "min-w-full border-collapse",
                        thead { class: "bg-muted",
                            tr {
                                Th { "#" }
                                Th { "ID" }
                                Th { "Model" }
                                Th { "Temp (\u{00b0}C)" }
                                Th { "Moisture (%)" }
                                Th { "pH" }
                                Th { "EC (\u{03bc}S/cm)" }
                                Th { "Salinity (mg/L)" }
                                Th { "TDS (ppm)" }
                                Th { "Temp Cal" }
                                Th { "Moist Cal" }
                                Th { "EC Cal" }
                                Th { "EC Temp Coeff" }
                                Th { "Sal Coeff" }
                                Th { "TDS Coeff" }
                                Th { "Time" }
                            }
                        }
                        tbody {
                            if soil_readings.read().is_empty() {
                                tr {
                                    td { colspan: "16", class: "px-4 py-10 text-center",
                                        div { class: "flex flex-col items-center gap-2",
                                            lucide_dioxus::Sprout { class: "w-9 h-9 text-muted-foreground" }
                                            h3 { class: "text-sm font-medium text-foreground", "No readings yet" }
                                            p { class: "text-sm text-muted-foreground", "Data streams automatically every 5 seconds" }
                                        }
                                    }
                                }
                            }
                            for row in soil_readings.read().iter().rev() {
                                {
                                    let ph = row.ph.map(|value| format!("{value:.1}")).unwrap_or_else(|| "\u{2014}".into());
                                    let conductivity = row.conductivity.map(|value| value.to_string()).unwrap_or_else(|| "\u{2014}".into());
                                    let salinity = row.salinity.map(|value| value.to_string()).unwrap_or_else(|| "\u{2014}".into());
                                    let tds = row.tds.map(|value| value.to_string()).unwrap_or_else(|| "\u{2014}".into());
                                    let temperature_calibration = row.temperature_calibration.map(|value| format!("{value:.1}")).unwrap_or_else(|| "\u{2014}".into());
                                    let moisture_calibration = row.moisture_calibration.map(|value| format!("{value:.1}")).unwrap_or_else(|| "\u{2014}".into());
                                    let conductivity_calibration = row.conductivity_calibration.map(|value| value.to_string()).unwrap_or_else(|| "\u{2014}".into());
                                    let conductivity_temperature_coefficient = row.conductivity_temperature_coefficient.map(|value| format!("{value:.1}")).unwrap_or_else(|| "\u{2014}".into());
                                    let salinity_coefficient = row.salinity_coefficient.map(|value| format!("{value:.2}")).unwrap_or_else(|| "\u{2014}".into());
                                    let tds_coefficient = row.tds_coefficient.map(|value| format!("{value:.2}")).unwrap_or_else(|| "\u{2014}".into());
                                    rsx! {
                                        tr { key: "{row.row}", class: "border-b border-border hover:bg-muted/40 transition-colors",
                                            Td { "{row.row}" }
                                            Td { class: "tabular-nums", "{row.address}" }
                                            Td { class: "font-mono text-xs", "{row.model}" }
                                            Td { class: "tabular-nums", "{row.temperature_celsius:.1}" }
                                            Td { class: "tabular-nums", "{row.moisture_percent:.1}" }
                                            Td { class: "tabular-nums", "{ph}" }
                                            Td { class: "tabular-nums", "{conductivity}" }
                                            Td { class: "tabular-nums", "{salinity}" }
                                            Td { class: "tabular-nums", "{tds}" }
                                            Td { class: "tabular-nums", "{temperature_calibration}" }
                                            Td { class: "tabular-nums", "{moisture_calibration}" }
                                            Td { class: "tabular-nums", "{conductivity_calibration}" }
                                            Td { class: "tabular-nums", "{conductivity_temperature_coefficient}" }
                                            Td { class: "tabular-nums", "{salinity_coefficient}" }
                                            Td { class: "tabular-nums", "{tds_coefficient}" }
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
