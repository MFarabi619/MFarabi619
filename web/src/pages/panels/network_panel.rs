use crate::api::{self, WifiNetwork, WirelessStatusData};
use super::{sleep_ms, Th, Td};
use dioxus::prelude::*;
use lucide_dioxus::{LoaderCircle, Radar, Wifi};
use ui::components::toast::use_toast;

#[component]
pub fn NetworkPanel(
    device_url: Signal<String>,
    wireless: Signal<Option<WirelessStatusData>>,
    networks: Signal<Vec<WifiNetwork>>,
    scanning: Signal<bool>,
    connecting: Signal<bool>,
    ssid_input: Signal<String>,
    password_input: Signal<String>,
) -> Element {
    let toasts = use_toast();

    let wireless_data = wireless.read();

    rsx! {
        section { id: "network-section", class: "flex flex-col h-full",
            if let Some(ref wireless_info) = *wireless_data {
                if wireless_info.ap_active {
                    div { class: "text-sm text-muted-foreground mb-3",
                        if !wireless_info.ap_ssid.is_empty() {
                            "AP: {wireless_info.ap_ssid} ({wireless_info.ap_ipv4})"
                        } else {
                            "AP: {wireless_info.ap_ipv4}"
                        }
                    }
                }
            }

            div { class: "mb-3",
                button {
                    class: "gold-button-outline text-sm w-full justify-center",
                    disabled: *scanning.read(),
                    onclick: move |_| {
                        scanning.set(true);
                        let url = device_url.read().clone();
                        spawn(async move {
                            match api::fetch_wifi_scan(&url).await {
                                Ok(response) => {
                                    let count = response.data.networks.len();
                                    networks.set(response.data.networks);
                                    toasts.success(format!("Found {count} network(s)"), None);
                                }
                                Err(error) => toasts.error(format!("Scan failed: {error}"), None),
                            }
                            scanning.set(false);
                        });
                    },
                    if *scanning.read() {
                        LoaderCircle { class: "w-4 h-4 animate-spin" }
                        "Scanning..."
                    } else {
                        Radar { class: "w-4 h-4" }
                        "Scan"
                    }
                }
            }

            // WiFi connect form
            form {
                class: "mt-2 flex flex-col lg:flex-row lg:items-end gap-2 mb-3",
                onsubmit: move |form_event| {
                    form_event.prevent_default();
                    let ssid = ssid_input.read().clone();
                    let password = password_input.read().clone();
                    if ssid.is_empty() { return; }
                    connecting.set(true);
                    let url = device_url.read().clone();
                    spawn(async move {
                        match api::connect_wifi(&url, &ssid, &password).await {
                            Ok(_) => {
                                toasts.success(format!("Connecting to {ssid}..."), None);
                                sleep_ms(3000).await;
                                if let Ok(response) = api::fetch_wireless_status(&url).await {
                                    wireless.set(Some(response.data));
                                }
                            }
                            Err(error) => toasts.error(format!("Connect failed: {error}"), None),
                        }
                        connecting.set(false);
                    });
                },
                div { class: "min-w-0 flex-1",
                    input {
                        class: "gold-input w-full px-3 py-2 text-sm",
                        r#type: "text",
                        placeholder: "SSID",
                        value: "{ssid_input}",
                        oninput: move |event| ssid_input.set(event.value()),
                    }
                }
                div { class: "min-w-0 flex-1",
                    input {
                        class: "gold-input w-full px-3 py-2 text-sm",
                        r#type: "password",
                        placeholder: "Password (blank for open)",
                        value: "{password_input}",
                        oninput: move |event| password_input.set(event.value()),
                    }
                }
                div { class: "lg:w-auto lg:flex-none",
                    button {
                        class: "gold-button-outline text-sm whitespace-nowrap",
                        r#type: "submit",
                        disabled: ssid_input.read().is_empty() || *connecting.read(),
                        if *connecting.read() {
                            LoaderCircle { class: "w-4 h-4 animate-spin" }
                            "Connecting..."
                        } else {
                            Wifi { class: "w-4 h-4" }
                            "Connect"
                        }
                    }
                }
            }

            // Scan results table
            div { class: "overflow-auto flex-1 border border-border rounded-lg",
                table { class: "w-full border-collapse min-w-[420px]",
                    thead {
                        tr {
                            Th { "SSID" }
                            Th { "RSSI" }
                            Th { "CHANNEL" }
                            Th { "SECURITY" }
                        }
                    }
                    tbody {
                        if networks.read().is_empty() {
                            tr {
                                td { colspan: "4", class: "text-muted-foreground text-sm px-3 py-2 border-b border-border",
                                    "Run a scan to list nearby WiFi networks."
                                }
                            }
                        }
                        for (network_index, network) in networks.read().iter().enumerate() {
                            {
                                let is_connected_network = wireless_data.as_ref()
                                    .is_some_and(|wireless_info| wireless_info.sta_ssid == network.ssid && !network.ssid.is_empty());
                                let row_class = if is_connected_network {
                                    "border-b border-border bg-emerald-500/10"
                                } else {
                                    "border-b border-border hover:bg-muted/30 transition-colors"
                                };
                                let ssid_display = if network.ssid.is_empty() { "(hidden)".to_string() } else { network.ssid.clone() };
                                let ssid_for_click = network.ssid.clone();
                                let ssid_class = if is_connected_network {
                                    "border-0 bg-transparent p-0 cursor-pointer transition-colors hover:text-accent text-emerald-400 font-semibold"
                                } else if network.ssid.is_empty() {
                                    "border-0 bg-transparent p-0 cursor-pointer transition-colors hover:text-accent text-muted-foreground italic"
                                } else {
                                    "border-0 bg-transparent p-0 cursor-pointer transition-colors hover:text-accent text-primary underline"
                                };

                                rsx! {
                                    tr { key: "{network_index}-{ssid_display}", class: "{row_class}",
                                        td { class: "px-3 py-2 text-sm",
                                            button {
                                                class: "{ssid_class}",
                                                onclick: move |_| ssid_input.set(ssid_for_click.clone()),
                                                "{ssid_display}"
                                            }
                                            if is_connected_network {
                                                span { class: "ml-2 text-xs bg-emerald-500/20 text-emerald-400 rounded px-1.5 py-0.5",
                                                    "{wireless_data.as_ref().map(|wireless_info| wireless_info.sta_ipv4.as_str()).unwrap_or(\"\")}"
                                                }
                                            }
                                        }
                                        Td { class: "font-mono", "{network.rssi}" }
                                        Td { class: "font-mono", "{network.channel}" }
                                        Td { class: "text-muted-foreground", "{network.encryption}" }
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
