use crate::api::{self, DEFAULT_DEVICE_URL};
use crate::components::api_modal::ApiModal;
use crate::components::command_palette::CommandPalette;
use crate::pages::panels::{
    fetch_and_add_sensor_readings, sleep_ms,
    Co2Row, TemperatureHumidityRow, VoltageRow,
    BluetoothPanel, FilesystemPanel, FlashPanel, MeasurementPanel, MeasurementTab, NetworkPanel, TerminalPanel,
    ENABLE_TEMPERATURE_HUMIDITY,
};
use dioxus::prelude::*;
use lucide_dioxus::Timer;
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

    // Connection state
    let mut is_connected = use_signal(|| false);
    let mut error_message = use_signal(|| None::<String>);

    // Device data
    let mut status = use_signal(|| None::<api::DeviceStatusData>);
    let mut wireless = use_signal(|| None::<api::WirelessStatusData>);
    let mut networks = use_signal(Vec::<api::WifiNetwork>::new);
    let mut files = use_signal(Vec::<api::FileEntry>::new);
    let mut littlefs_files = use_signal(Vec::<api::FileEntry>::new);
    let mut littlefs_total_bytes = use_signal(|| 0u64);
    let mut littlefs_used_bytes = use_signal(|| 0u64);

    // Measurements
    let mut active_tab = use_signal(|| {
        if ENABLE_TEMPERATURE_HUMIDITY {
            MeasurementTab::TemperatureHumidity
        } else {
            MeasurementTab::CarbonDioxide
        }
    });
    let mut co2_readings = use_signal(Vec::<Co2Row>::new);
    let mut temperature_humidity_readings = use_signal(Vec::<TemperatureHumidityRow>::new);
    let mut voltage_readings = use_signal(Vec::<VoltageRow>::new);
    let last_event_time = use_signal(String::new);
    let mut co2_config = use_signal(|| None::<api::Co2ConfigData>);
    let mut sampling = use_signal(|| false);
    let mut api_modal_open = use_signal(|| false);

    let mut polling_enabled = use_signal(|| true);
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

    // Storage progress
    let storage_percent = use_memo(move || {
        status
            .read()
            .as_ref()
            .map(|status_data| status_data.storage.percent_used())
            .unwrap_or(0.0)
    });

    // ── Polling coroutine ──
    let toasts = Toasts;
    use_coroutine(move |_: UnboundedReceiver<()>| async move {
        let mut tick: u32 = 0;
        loop {
            if !*polling_enabled.peek() {
                sleep_ms(1_000).await;
                continue;
            }
            let url = device_url.read().clone();

            // CO2 config on first tick
            if tick == 0 {
                if let Ok(response) = api::fetch_co2_config(&url).await {
                    co2_config.set(Some(response.data));
                }
            }

            // Device status every 10s
            if tick % 2 == 0 {
                let was_connected = *is_connected.peek();
                match api::fetch_device_status(&url).await {
                    Ok(envelope) => {
                        *crate::DEVICE_CHIP_MODEL.write() =
                            envelope.data.device.chip_model.clone();
                        *crate::DEVICE_UPTIME.write() = envelope.data.runtime.uptime.clone();
                        {
                            let used_kb = (envelope.data.runtime.memory_heap_total.saturating_sub(envelope.data.runtime.memory_heap_bytes)) / 1024;
                            let total_kb = envelope.data.runtime.memory_heap_total / 1024;
                            *crate::DEVICE_HEAP_FREE.write() = format!("{used_kb}/{total_kb} KB");
                        }

                        status.set(Some(envelope.data));
                        is_connected.set(true);
                        error_message.set(None);

                        if !was_connected {
                            let ssid = crate::WIFI_SSID.read().clone();
                            let ip = crate::WIFI_IP.read().clone();
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
                        error_message.set(Some(format!("{error}")));
                    }
                }
            }

            // Wireless status every 10s
            if tick % 2 == 0 {
                if let Ok(response) = api::fetch_wireless_status(&url).await {
                    *crate::WIFI_SSID.write() = response.data.sta_ssid.clone();
                    *crate::WIFI_RSSI.write() = response.data.wifi_rssi;
                    *crate::WIFI_IP.write() = response.data.sta_ipv4.clone();
                    wireless.set(Some(response.data));
                }
            }

            if !*sampling.peek() {
                fetch_and_add_sensor_readings(
                    &url, last_event_time, co2_readings, temperature_humidity_readings, voltage_readings,
                ).await;
            }

            // Filesystem every 30s
            if tick % 6 == 0 {
                if let Ok(entries) = api::fetch_filesystem(&url, "sd").await {
                    files.set(entries);
                }
                if let Ok(entries) = api::fetch_filesystem(&url, "littlefs").await {
                    littlefs_files.set(entries);
                }
                if let Ok(envelope) =
                    api::fetch_device_status_for_location(&url, "littlefs").await
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
                            fetch_and_add_sensor_readings(
                                &url, last_event_time, co2_readings, temperature_humidity_readings, voltage_readings,
                            ).await;
                            sampling.set(false);
                        });
                    }
                }
            },

            // Device URL bar
            div { class: "flex items-center gap-3",
                {
                    let full_url = device_url.read().clone();
                    let (protocol, display_host) = if full_url.starts_with("https://") {
                        ("https://", full_url.strip_prefix("https://").unwrap_or(&full_url).to_string())
                    } else {
                        ("http://", full_url.strip_prefix("http://").unwrap_or(&full_url).to_string())
                    };
                    let protocol_owned = protocol.to_string();
                    rsx! {
                        div { class: "flex flex-1 rounded-lg border border-border bg-background overflow-hidden",
                            button {
                                class: "px-3 py-2 text-sm font-mono text-muted-foreground bg-muted/30 border-r border-border select-none shrink-0 hover:text-foreground transition-colors cursor-pointer",
                                title: "Click to toggle http/https",
                                onclick: move |_| {
                                    let current = device_url.read().clone();
                                    let toggled = if current.starts_with("https://") {
                                        current.replacen("https://", "http://", 1)
                                    } else {
                                        current.replacen("http://", "https://", 1)
                                    };
                                    device_url.set(toggled.clone());
                                    #[cfg(target_arch = "wasm32")]
                                    if let Some(storage) = web_sys::window()
                                        .and_then(|w| w.local_storage().ok().flatten())
                                    {
                                        let _ = storage.set_item("device_url", &toggled);
                                    }
                                },
                                "{protocol_owned}"
                            }
                            input {
                                class: "flex-1 px-3 py-2 text-sm font-mono bg-transparent text-foreground outline-none",
                                r#type: "text",
                                value: "{display_host}",
                                oninput: move |event| {
                                    let hostname = event.value();
                                    let new_url = if hostname.starts_with("http://") || hostname.starts_with("https://") {
                                        hostname.clone()
                                    } else {
                                        let current = device_url.read().clone();
                                        let prefix = if current.starts_with("https://") { "https://" } else { "http://" };
                                        format!("{prefix}{hostname}")
                                    };
                                    device_url.set(new_url.clone());
                                    #[cfg(target_arch = "wasm32")]
                                    if let Some(storage) = web_sys::window()
                                        .and_then(|w| w.local_storage().ok().flatten())
                                    {
                                        let _ = storage.set_item("device_url", &new_url);
                                    }
                                },
                            }
                        }
                    }
                }
                // Interval selector — flagged off for now
                div { class: "hidden items-center gap-1.5 shrink-0",
                    Timer { class: "w-3.5 h-3.5 text-muted-foreground" }
                    select {
                        class: "bg-transparent border border-border rounded px-1.5 py-1 text-xs font-mono text-foreground cursor-pointer outline-none",
                        onchange: move |event| {
                            if let Ok(ms) = event.value().parse::<u32>() {
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
                    let polling = *polling_enabled.read();
                    let ip = crate::WIFI_IP.read().clone();
                    let ssid = crate::WIFI_SSID.read().clone();
                    let rssi = *crate::WIFI_RSSI.read();

                    let (dot_class, ping_class) = if !polling {
                        ("bg-gray-500", "")
                    } else if connected {
                        ("bg-emerald-400", "absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-70 animate-ping")
                    } else {
                        ("bg-amber-500", "absolute inline-flex h-full w-full rounded-full bg-amber-500 opacity-70 animate-pulse")
                    };

                    let label = if !polling {
                        "PAUSED".to_string()
                    } else if connected && !ip.is_empty() {
                        ip.clone()
                    } else if connected {
                        "LIVE".to_string()
                    } else {
                        "POLLING".to_string()
                    };

                    let tooltip = if !polling {
                        "Click to resume polling".to_string()
                    } else if !ssid.is_empty() {
                        format!("{ssid} ({rssi} dBm) \u{2014} click to pause")
                    } else {
                        "Click to pause polling".to_string()
                    };

                    rsx! {
                        button {
                            class: "flex items-center gap-2 rounded-full border border-border bg-background/60 px-3 py-1.5 text-xs font-mono text-foreground shrink-0 cursor-pointer hover:bg-muted/50 transition-colors",
                            title: "{tooltip}",
                            onclick: move |_| {
                                let new_val = !*polling_enabled.peek();
                                polling_enabled.set(new_val);
                                #[cfg(target_arch = "wasm32")]
                                if let Some(s) = web_sys::window().and_then(|w| w.local_storage().ok().flatten()) {
                                    let _ = s.set_item("polling_enabled", if new_val { "true" } else { "false" });
                                }
                            },
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

            // Measurements + Filesystem
            div { class: "grid grid-cols-1 md:grid-cols-[3fr_1fr] gap-3.5",
                MeasurementPanel {
                    device_url,
                    last_event_time,
                    co2_readings,
                    temperature_humidity_readings,
                    voltage_readings,
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

            TerminalPanel { device_url }

            FlashPanel {}

            // BluetoothPanel {}

            if let Some(ref error) = *error_message.read() {
                div { class: "rounded-lg border border-destructive/30 bg-destructive/10 px-4 py-3 text-sm text-destructive flex items-center justify-between gap-3",
                    span { "{error}" }
                    button {
                        class: "shrink-0 px-3 py-1 rounded border border-destructive/50 text-xs hover:bg-destructive/20 transition-colors",
                        onclick: move |_| {
                            #[cfg(target_arch = "wasm32")]
                            if let Some(s) = web_sys::window().and_then(|w| w.local_storage().ok().flatten()) {
                                s.clear().ok();
                            }
                            document::eval("location.reload()");
                        },
                        "Clear Cache & Reload"
                    }
                }
            }
        }

        CommandPalette {
            on_open_api: move |_| api_modal_open.set(true),
            on_sample: move |_| {
                if !*sampling.read() {
                    sampling.set(true);
                    let url = device_url.read().clone();
                    spawn(async move {
                        fetch_and_add_sensor_readings(
                            &url, last_event_time, co2_readings, temperature_humidity_readings, voltage_readings,
                        ).await;
                        sampling.set(false);
                    });
                }
            },
            on_scan_networks: move |_| {
                scanning.set(true);
                let url = device_url.read().clone();
                spawn(async move {
                    if let Ok(response) = api::fetch_wifi_scan(&url).await {
                        networks.set(response.data.networks);
                    }
                    scanning.set(false);
                });
            },
            on_refresh_files: move |_| {
                let url = device_url.read().clone();
                spawn(async move {
                    if let Ok(entries) = api::fetch_filesystem(&url, "sd").await {
                        files.set(entries);
                    }
                });
            },
            on_upload: move |_| {
                document::eval("document.getElementById('sd-upload-input')?.click()");
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
                        if let Ok(response) = api::fetch_wifi_scan(&url).await {
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
                    onclick: move |_| *crate::SHOW_NETWORK_SHEET.write() = false,
                }
                div {
                    class: panel_class,
                    onmouseleave: move |_| *crate::SHOW_NETWORK_SHEET.write() = false,
                    onclick: move |e| e.stop_propagation(),
                    div { class: "p-4 h-full flex flex-col",
                        div { class: "flex items-center justify-between mb-4 shrink-0",
                            h2 { class: "text-lg font-semibold", "Network" }
                            button {
                                class: "p-1 rounded hover:bg-muted/50 transition-colors text-muted-foreground",
                                onclick: move |_| *crate::SHOW_NETWORK_SHEET.write() = false,
                                lucide_dioxus::X { class: "w-5 h-5" }
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
