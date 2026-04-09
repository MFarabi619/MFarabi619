use crate::api::{self, DEFAULT_DEVICE_URL};
use crate::components::command_palette::CommandPalette;
use crate::pages::panels::{
    fetch_and_add_sensor_readings, sleep_ms,
    Co2Row, TemperatureHumidityRow, VoltageRow,
    FilesystemPanel, MeasurementPanel, MeasurementTab, NetworkPanel,
    ENABLE_TEMPERATURE_HUMIDITY,
};
use dioxus::prelude::*;
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
    let mut co2_config = use_signal(|| None::<api::Co2ConfigData>);
    let mut sampling = use_signal(|| false);

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
                        *crate::DEVICE_HEAP_FREE.write() =
                            format!("{} B free", envelope.data.runtime.memory_heap_bytes);

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

            // All sensors from CloudEvents every 5s
            fetch_and_add_sensor_readings(
                &url, co2_readings, temperature_humidity_readings, voltage_readings,
            ).await;

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
            sleep_ms(5_000).await;
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
                if keyboard_event.modifiers().ctrl() && keyboard_event.key() == Key::Enter {
                    keyboard_event.prevent_default();
                    if !*sampling.read() {
                        sampling.set(true);
                        let url = device_url.read().clone();
                        spawn(async move {
                            fetch_and_add_sensor_readings(
                                &url, co2_readings, temperature_humidity_readings, voltage_readings,
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
                    let display_host = full_url.strip_prefix("http://").unwrap_or(&full_url).to_string();
                    rsx! {
                        div { class: "flex flex-1 rounded-lg border border-border bg-background overflow-hidden",
                            span { class: "px-3 py-2 text-sm font-mono text-muted-foreground bg-muted/30 border-r border-border select-none shrink-0", "http://" }
                            input {
                                class: "flex-1 px-3 py-2 text-sm font-mono bg-transparent text-foreground outline-none",
                                r#type: "text",
                                value: "{display_host}",
                                oninput: move |event| {
                                    let hostname = event.value();
                                    let new_url = if hostname.starts_with("http://") || hostname.starts_with("https://") {
                                        hostname.clone()
                                    } else {
                                        format!("http://{hostname}")
                                    };
                                    device_url.set(new_url.clone());
                                    #[cfg(target_arch = "wasm32")]
                                    if let Some(storage) = web_sys::window()
                                        .and_then(|window| window.local_storage().ok().flatten())
                                    {
                                        let _ = storage.set_item("device_url", &new_url);
                                    }
                                },
                            }
                        }
                    }
                }
                {
                    let connected = *is_connected.read();
                    let ip = crate::WIFI_IP.read().clone();
                    let ssid = crate::WIFI_SSID.read().clone();
                    let rssi = *crate::WIFI_RSSI.read();

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
                    } else {
                        String::new()
                    };

                    rsx! {
                        div {
                            class: "flex items-center gap-2 rounded-full border border-border bg-background/60 px-3 py-1.5 text-xs font-mono text-foreground shrink-0",
                            title: "{tooltip}",
                            span { class: "relative flex h-2 w-2",
                                span { class: "{ping_class}" }
                                span { class: "relative inline-flex h-2 w-2 rounded-full {dot_class}" }
                            }
                            span { class: "font-medium", "{label}" }
                        }
                    }
                }
            }

            // Measurements
            MeasurementPanel {
                device_url,
                co2_readings,
                temperature_humidity_readings,
                voltage_readings,
                co2_config,
                sampling,
                active_tab,
            }

            // Bottom row: Network + Filesystem
            div { class: "grid grid-cols-1 md:grid-cols-[2fr_1fr] gap-3.5",
                NetworkPanel {
                    device_url,
                    wireless,
                    networks,
                    scanning,
                    connecting,
                    ssid_input,
                    password_input,
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

            // Error
            if let Some(ref error) = *error_message.read() {
                div { class: "rounded-2xl border border-destructive/30 bg-destructive/10 px-4 py-3 text-sm text-destructive",
                    "{error}"
                }
            }
        }

        // Command Palette
        CommandPalette {
            on_open_api: move |_| {},
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
        }
    }
}
