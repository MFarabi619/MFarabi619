use crate::api::{self, DEFAULT_DEVICE_URL};
use crate::components::api_modal::ApiModal;
use crate::components::command_palette::CommandPalette;
use crate::hooks::sleep_ms;
use crate::services::{Co2Service, DeviceService, FileService, WifiService};
use crate::pages::panels::{
    fetch_and_add_sensor_readings, load_inventory,
    MeasurementState, SensorAvailability,
    BluetoothPanel, FilesystemPanel, FlashPanel, MeasurementPanel, MeasurementTab, NetworkPanel, SleepPanel, TerminalPanel,
};
use dioxus::prelude::*;
use lucide_dioxus::{Timer, X};
use ui::components::button::{Button, ButtonSize, ButtonVariant};
use ui::components::input::Input;
use ui::components::toast::Toasts;

#[component]
pub fn Home() -> Element {
    let mut device_url = use_signal(|| {
        #[cfg(target_arch = "wasm32")]
        {
            // Load from localStorage, fall back to mDNS default
            web_sys::window()
                .and_then(|window| window.local_storage().ok().flatten())
                .and_then(|storage| storage.get_item("device_url").ok().flatten())
                .unwrap_or_else(|| DEFAULT_DEVICE_URL.to_string())
        }
        #[cfg(not(target_arch = "wasm32"))]
        {
            DEFAULT_DEVICE_URL.to_string()
        }
    });

    let mut device_ctx = use_context::<crate::DeviceContext>();

    // Connection state
    let mut is_connected = use_signal(|| false);
    let mut resolved_url = use_signal(String::new);

    // Device data
    let mut status = use_signal(|| None::<api::DeviceStatusData>);
    let mut wireless = use_signal(|| None::<api::WirelessStatusData>);
    let mut networks = use_signal(Vec::<api::WifiNetwork>::new);
    let mut files = use_signal(Vec::<api::FileEntry>::new);
    let mut littlefs_files = use_signal(Vec::<api::FileEntry>::new);
    let mut littlefs_total_bytes = use_signal(|| 0u64);
    let mut littlefs_used_bytes = use_signal(|| 0u64);

    // Measurements
    let mut measurement = use_signal(|| MeasurementState {
        last_event_time: Signal::new(String::new()),
        availability: Signal::new(SensorAvailability::default()),
        co2_readings: Signal::new(Vec::new()),
        temperature_humidity_readings: Signal::new(Vec::new()),
        voltage_readings: Signal::new(Vec::new()),
        pressure_readings: Signal::new(Vec::new()),
    });
    let mut active_tab = use_signal(|| MeasurementTab::TemperatureHumidity);
    let mut co2_config = use_signal(|| None::<api::Co2ConfigData>);
    let mut sampling = use_signal(|| false);
    let mut api_modal_open = use_signal(|| false);

    let mut poll_interval_ms = use_signal(|| {
        #[cfg(target_arch = "wasm32")]
        {
            web_sys::window()
                .and_then(|w| w.local_storage().ok().flatten())
                .and_then(|s| s.get_item("poll_interval_ms").ok().flatten())
                .and_then(|v| v.parse::<u32>().ok())
                .unwrap_or(1000)
        }
        #[cfg(not(target_arch = "wasm32"))]
        1000u32
    });

    // Network UI state
    let mut scanning = use_signal(|| false);
    let mut connecting = use_signal(|| false);
    let mut ssid_input = use_signal(String::new);
    let mut password_input = use_signal(String::new);

    // Derived WiFi state from wireless signal — avoids duplicating data in separate signals
    let wifi_ssid = use_memo(move || {
        wireless.read().as_ref().map(|w| w.sta_ssid.clone()).unwrap_or_default()
    });
    let wifi_rssi = use_memo(move || {
        wireless.read().as_ref().map(|w| w.wifi_rssi).unwrap_or(0)
    });
    let wifi_ip = use_memo(move || {
        wireless.read().as_ref().map(|w| w.sta_ipv4.clone()).unwrap_or_default()
    });


    // Storage progress
    let storage_percent = use_memo(move || {
        status
            .read()
            .as_ref()
            .map(|status_data| status_data.storage.percent_used())
            .unwrap_or(0.0)
    });

    use_effect(move || {
        let _ = device_url.read();
        resolved_url.set(String::new());
    });

    // ── Polling loop ──
    let toasts = Toasts;
    let mut poller = use_future(move || async move {
        let mut tick: u32 = 0;
        loop {
            let resolved = resolved_url.peek().clone();
            let url = if resolved.is_empty() {
                device_url.read().clone()
            } else {
                resolved
            };

            // CO2 config on first tick
            if tick == 0 {
                if let Ok(response) = Co2Service::get_config(&url).await {
                    co2_config.set(Some(response.data));
                }
            }

            // Device status every 10s
            if tick % 2 == 0 {
                let was_connected = *is_connected.peek();
                match DeviceService::get_status(&url).await {
                    Ok(envelope) => {
                        device_ctx.chip_model.set(envelope.data.device.chip_model.clone());
                        {
                            let free_kb = envelope.data.runtime.memory_heap_free / 1024;
                            let total_kb = envelope.data.runtime.memory_heap_total / 1024;
                            device_ctx.heap_memory.set(format!("{free_kb}/{total_kb} KB"));
                        }

                        if resolved_url.peek().is_empty() {
                            let ip = &envelope.data.network.ipv4_address;
                            if !ip.is_empty() {
                                let protocol = if url.starts_with("https://") { "https://" } else { "http://" };
                                resolved_url.set(format!("{protocol}{ip}"));
                            }
                        }

                        status.set(Some(envelope.data));
                        is_connected.set(true);
                        if !was_connected {
                            let ssid = wifi_ssid.read().clone();
                            let ip = wifi_ip.read().clone();
                            if !ssid.is_empty() {
                                toasts.success(format!("Connected to {ssid} ({ip})"), None);
                            } else {
                                toasts.success(format!("Connected to {url}"), None);
                            }
                        }
                    }
                    Err(error) => {
                        if was_connected {
                            toasts.error(format!("Disconnected: {error}"), None);
                        }
                        is_connected.set(false);
                        resolved_url.set(String::new());
                    }
                }
            }

            // Wireless status every 10s
            if tick % 2 == 0 {
                if let Ok(response) = WifiService::get_status(&url).await {
                    wireless.set(Some(response.data));
                }
            }

            // Load sensor inventory at startup
            if tick == 0 {
                let mut avail = *measurement.read().availability.read();
                if load_inventory(&url, &mut avail).await {
                    measurement.write().availability.set(avail);
                }
            }

            if !*sampling.peek() {
                fetch_and_add_sensor_readings(&url, measurement).await;
            }

            // Filesystem every 30s
            if tick % 6 == 0 {
                if let Ok(entries) = FileService::list(&url, "sd").await {
                    files.set(entries);
                }
                if let Ok(entries) = FileService::list(&url, "littlefs").await {
                    littlefs_files.set(entries);
                }
                if let Ok(envelope) =
                    DeviceService::get_status_for_location(&url, "littlefs").await
                {
                    littlefs_total_bytes.set(envelope.data.storage.total_bytes);
                    littlefs_used_bytes.set(envelope.data.storage.used_bytes);
                }
            }

            tick = tick.wrapping_add(1);
            let interval = *poll_interval_ms.peek();
            sleep_ms(interval).await;
        }
    });

    rsx! {
        div {
            class: "space-y-3.5",
            tabindex: "0",
            onkeydown: move |keyboard_event: KeyboardEvent| {
                if keyboard_event.modifiers().ctrl()
                    && keyboard_event.key() == Key::Character("k".into())
                {
                    keyboard_event.prevent_default();
                    *crate::SHOW_COMMAND_PALETTE.write() = true;
                }
                if keyboard_event.modifiers().ctrl()
                    && keyboard_event.key() == Key::Character("/".into())
                {
                    keyboard_event.prevent_default();
                    api_modal_open.toggle();
                }
                if keyboard_event.modifiers().ctrl() && keyboard_event.key() == Key::Enter {
                    keyboard_event.prevent_default();
                    if !*sampling.read() {
                        sampling.set(true);
                        let url = device_url.read().clone();
                        spawn(async move {
                            fetch_and_add_sensor_readings(&url, measurement).await;
                            sampling.set(false);
                        });
                    }
                }
            },

            // Device URL bar
            div { class: "flex items-center gap-3",
                div { class: "flex-1 rounded-lg border border-border bg-background overflow-hidden",
                    Input {
                        class: Some("w-full border-0 h-auto px-3 py-2 text-sm font-mono bg-transparent text-foreground focus:ring-0 focus:ring-offset-0".to_string()),
                        input_type: "text".to_string(),
                        aria_label: Some("Device URL".to_string()),
                        value: device_url.read().clone(),
                        on_input: Some(Callback::new(move |event: FormEvent| {
                            let new_url = event.value();
                            device_url.set(new_url.clone());
                            #[cfg(target_arch = "wasm32")]
                            if let Some(storage) = web_sys::window()
                                .and_then(|w| w.local_storage().ok().flatten())
                            {
                                let _ = storage.set_item("device_url", &new_url);
                            }
                        })),
                    }
                }
                // Interval selector — flagged off for now
                div { class: "hidden items-center gap-1.5 shrink-0",
                    Timer { class: "w-3.5 h-3.5 text-muted-foreground" }
                    select {
                        class: "bg-transparent border border-border rounded px-1.5 py-1 text-xs font-mono text-foreground cursor-pointer outline-none",
                        onchange: move |event: FormEvent| {
                            if let Ok(ms) = event.parsed::<u32>() {
                                poll_interval_ms.set(ms);
                                #[cfg(target_arch = "wasm32")]
                                if let Some(s) = web_sys::window().and_then(|w| w.local_storage().ok().flatten()) {
                                    let _ = s.set_item("poll_interval_ms", &ms.to_string());
                                }
                            }
                        },
                        option { value: "1000", selected: *poll_interval_ms.read() == 1000, "1s" }
                        option { value: "2000", selected: *poll_interval_ms.read() == 2000, "2s" }
                        option { value: "5000", selected: *poll_interval_ms.read() == 5000, "5s" }
                        option { value: "10000", selected: *poll_interval_ms.read() == 10000, "10s" }
                        option { value: "30000", selected: *poll_interval_ms.read() == 30000, "30s" }
                        option { value: "60000", selected: *poll_interval_ms.read() == 60000, "60s" }
                    }
                }
                {
                    let connected = *is_connected.read();
                    let ip = wifi_ip.read().clone();
                    let ssid = wifi_ssid.read().clone();
                    let rssi = *wifi_rssi.read();

                    let (dot_class, ping_class) = if connected {
                        ("bg-emerald-400", "absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-70 animate-ping")
                    } else {
                        ("bg-amber-500", "absolute inline-flex h-full w-full rounded-full bg-amber-500 opacity-70 animate-pulse")
                    };

                    let label = if connected && !ip.is_empty() {
                        ip.clone()
                    } else if connected {
                        "LIVE".to_string()
                    } else {
                        "POLLING".to_string()
                    };

                    let tooltip = if !ssid.is_empty() {
                        format!("{ssid} ({rssi} dBm)")
                    } else if connected {
                        "Connected".to_string()
                    } else {
                        "Polling for device...".to_string()
                    };

                    let href = if connected && !ip.is_empty() {
                        Some(format!("http://{ip}"))
                    } else {
                        None
                    };

                    rsx! {
                        if let Some(ref url) = href {
                            a {
                                class: "flex items-center gap-2 rounded-full border border-border bg-background/60 px-3 py-1.5 text-xs font-mono text-foreground shrink-0 hover:border-primary/50 transition-colors cursor-pointer",
                                title: "{tooltip}",
                                aria_label: "{label}",
                                href: "{url}",
                                target: "_blank",
                                span { class: "relative flex h-2 w-2",
                                    if !ping_class.is_empty() {
                                        span { class: "{ping_class}" }
                                    }
                                    span { class: "relative inline-flex h-2 w-2 rounded-full {dot_class}" }
                                }
                                span { class: "font-medium", "{label}" }
                            }
                        } else {
                            div {
                                class: "flex items-center gap-2 rounded-full border border-border bg-background/60 px-3 py-1.5 text-xs font-mono text-foreground shrink-0",
                                title: "{tooltip}",
                                aria_label: "{label}",
                                span { class: "relative flex h-2 w-2",
                                    if !ping_class.is_empty() {
                                        span { class: "{ping_class}" }
                                    }
                                    span { class: "relative inline-flex h-2 w-2 rounded-full {dot_class}" }
                                }
                                span { class: "font-medium", "{label}" }
                            }
                        }
                    }
                }
            }

            // Measurements + Filesystem
            div { class: "grid grid-cols-1 md:grid-cols-[3fr_1fr] gap-3.5",
                MeasurementPanel {
                    device_url,
                    measurement,
                    co2_config,
                    sampling,
                    active_tab,
                }

                FilesystemPanel {
                    device_url,
                    files,
                    littlefs_files,
                    littlefs_total_bytes,
                    littlefs_used_bytes,
                    status,
                    storage_percent,
                }
            }

            // SleepPanel { device_url, status }

            TerminalPanel { device_url }

            FlashPanel {}

            // BluetoothPanel {}

        }

        CommandPalette {
            on_open_api: move |_| api_modal_open.set(true),
            on_sample: move |_| {
                if !*sampling.read() {
                    sampling.set(true);
                    let url = device_url.read().clone();
                    spawn(async move {
                        fetch_and_add_sensor_readings(&url, measurement).await;
                        sampling.set(false);
                    });
                }
            },
            on_scan_networks: move |_| {
                scanning.set(true);
                let url = device_url.read().clone();
                spawn(async move {
                    if let Ok(response) = WifiService::scan(&url).await {
                        networks.set(response.data.networks);
                    }
                    scanning.set(false);
                });
            },
            on_refresh_files: move |_| {
                let url = device_url.read().clone();
                spawn(async move {
                    if let Ok(entries) = FileService::list(&url, "sd").await {
                        files.set(entries);
                    }
                });
            },
            on_upload: move |_| {
                #[cfg(target_arch = "wasm32")]
                if let Some(el) = web_sys::window()
                    .and_then(|w| w.document())
                    .and_then(|d| d.get_element_by_id("sd-upload-input"))
                {
                    use wasm_bindgen::JsCast;
                    if let Ok(input) = el.dyn_into::<web_sys::HtmlElement>() {
                        input.click();
                    }
                }
            },
        }

        ApiModal { open: api_modal_open, device_url }

        // ── Auto-scan when network sheet opens ──
        {
            let mut did_auto_scan = use_signal(|| false);
            use_effect(move || {
                let is_open = *crate::SHOW_NETWORK_SHEET.read();
                if is_open && !*did_auto_scan.peek() {
                    did_auto_scan.set(true);
                    scanning.set(true);
                    let url = device_url.peek().clone();
                    spawn(async move {
                        if let Ok(response) = WifiService::scan(&url).await {
                            networks.set(response.data.networks);
                        }
                        scanning.set(false);
                    });
                }
                if !is_open {
                    did_auto_scan.set(false);
                }
            });
            rsx! {}
        }

        {
            let sheet_open = *crate::SHOW_NETWORK_SHEET.read();
            let overlay_class = if sheet_open {
                "fixed inset-0 z-50 bg-black/60 transition-opacity duration-300 ease-in-out opacity-100"
            } else {
                "fixed inset-0 z-50 bg-black/60 transition-opacity duration-300 ease-in-out opacity-0 pointer-events-none"
            };
            let panel_class = if sheet_open {
                "fixed inset-y-0 right-0 z-50 w-full sm:w-[520px] bg-background border-l border-border shadow-lg overflow-y-auto transition-transform duration-300 ease-in-out translate-x-0"
            } else {
                "fixed inset-y-0 right-0 z-50 w-full sm:w-[520px] bg-background border-l border-border shadow-lg overflow-y-auto transition-transform duration-300 ease-in-out translate-x-full"
            };
            rsx! {
                div {
                    class: overlay_class,
                    aria_hidden: "true",
                    onclick: move |_| *crate::SHOW_NETWORK_SHEET.write() = false,
                }
                div {
                    class: panel_class,
                    role: "dialog",
                    aria_modal: "true",
                    aria_label: "Network settings",
                    onmouseleave: move |_| *crate::SHOW_NETWORK_SHEET.write() = false,
                    onclick: move |e| e.stop_propagation(),
                    div { class: "p-4 h-full flex flex-col",
                        div { class: "flex items-center justify-between mb-4 shrink-0",
                            div { class: "flex items-center gap-3 min-w-0",
                                h2 { class: "text-lg font-semibold shrink-0", "Network" }
                                if let Some(wireless_info) = wireless.read().as_ref() {
                                    if wireless_info.ap_active {
                                        if !wireless_info.ap_ssid.is_empty() {
                                            span { class: "inline-flex items-center rounded-full border border-border bg-background/60 px-2.5 py-1 text-xs font-mono text-foreground",
                                                "{wireless_info.ap_ssid}"
                                            }
                                        }
                                        if !wireless_info.ap_ipv4.is_empty() {
                                            span { class: "inline-flex items-center rounded-full border border-border bg-background/60 px-2.5 py-1 text-xs font-mono text-foreground",
                                                "{wireless_info.ap_ipv4}"
                                            }
                                        }
                                    }
                                }
                            }
                            Button {
                                variant: ButtonVariant::Ghost,
                                size: ButtonSize::Small,
                                is_icon_button: true,
                                aria_label: "Close".to_string(),
                                on_click: move |_| *crate::SHOW_NETWORK_SHEET.write() = false,
                                X { class: "w-5 h-5" }
                            }
                        }
                        NetworkPanel {
                            device_url,
                            wireless,
                            networks,
                            scanning,
                            connecting,
                            ssid_input,
                            password_input,
                        }
                    }
                }
            }
        }
    }
}
