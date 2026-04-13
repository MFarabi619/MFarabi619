use super::{Td, Th};
use crate::api::{WifiNetwork, WirelessStatusData};
use crate::hooks::sleep_ms;
use crate::services::{DeviceService, WifiService};
use dioxus::prelude::*;
use lucide_dioxus::{LoaderCircle, Radar, Wifi};
use ui::components::button::{Button, ButtonVariant};
use ui::components::input::Input;
use ui::components::label::Label;
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
    let mut selected_index = use_signal(|| None::<usize>);
    let ssid_input_label = use_signal(|| Some("network-ssid-input".to_string()));
    let password_input_label = use_signal(|| Some("network-password-input".to_string()));

    let wireless_data = wireless.read();

    rsx! {
        section { id: "network-section", class: "flex flex-col h-full",
            div { class: "mb-3",
                Button {
                    class: "gold-button-outline text-sm w-full justify-center".to_string(),
                    variant: ButtonVariant::Outline,
                    disabled: *scanning.read(),
                    loading: *scanning.read(),
                    on_click: move |_| {
                        scanning.set(true);
                        let url = device_url.read().clone();
                        spawn(async move {
                            match WifiService::scan(&url).await {
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
                    if !*scanning.read() {
                        Radar { class: "w-4 h-4" }
                    }
                    if *scanning.read() { "Scanning..." } else { "Scan" }
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
                        match WifiService::connect(&url, &ssid, &password).await {
                            Ok(_) => {
                                toasts.success(format!("Connecting to {ssid}..."), None);
                                sleep_ms(3000).await;
                                if let Ok(response) = WifiService::get_status(&url).await {
                                    wireless.set(Some(response.data));
                                }
                            }
                            Err(error) => toasts.error(format!("Connect failed: {error}"), None),
                        }
                        connecting.set(false);
                    });
                },
                div { class: "min-w-0 flex-1",
                    Label {
                        for_id: ssid_input_label,
                        class: Some("text-xs uppercase tracking-wider text-muted-foreground mb-2".to_string()),
                        "SSID"
                    }
                    Input {
                        id: Some("network-ssid-input".to_string()),
                        class: Some("gold-input w-full px-3 py-2 text-sm".to_string()),
                        input_type: "text".to_string(),
                        aria_label: Some("SSID".to_string()),
                        placeholder: "SSID".to_string(),
                        value: ssid_input.read().clone(),
                        on_input: Some(Callback::new(move |event: FormEvent| ssid_input.set(event.value()))),
                    }
                }
                div { class: "min-w-0 flex-1",
                    Label {
                        for_id: password_input_label,
                        class: Some("text-xs uppercase tracking-wider text-muted-foreground mb-2".to_string()),
                        "Password"
                    }
                    Input {
                        id: Some("network-password-input".to_string()),
                        class: Some("gold-input w-full px-3 py-2 text-sm".to_string()),
                        input_type: "password".to_string(),
                        aria_label: Some("Password".to_string()),
                        placeholder: "Password (blank for open)".to_string(),
                        value: password_input.read().clone(),
                        on_input: Some(Callback::new(move |event: FormEvent| password_input.set(event.value()))),
                    }
                }
                div { class: "lg:w-auto lg:flex-none",
                    Button {
                        class: "gold-button-outline text-sm whitespace-nowrap".to_string(),
                        variant: ButtonVariant::Outline,
                        button_type: "submit".to_string(),
                        disabled: ssid_input.read().is_empty() || *connecting.read(),
                        loading: *connecting.read(),
                        if !*connecting.read() {
                            Wifi { class: "w-4 h-4" }
                        }
                        if *connecting.read() { "Connecting..." } else { "Connect" }
                    }
                }
            }

            // Scan results table
            div {
                class: "overflow-auto flex-1 border border-border rounded-lg outline-none",
                tabindex: "0",
                onkeydown: move |e: KeyboardEvent| {
                    let count = networks.read().len();
                    if count == 0 { return; }
                    match e.key() {
                        Key::ArrowDown => {
                            e.prevent_default();
                            let next = match *selected_index.read() {
                                Some(i) => (i + 1) % count,
                                None => 0,
                            };
                            selected_index.set(Some(next));
                        }
                        Key::ArrowUp => {
                            e.prevent_default();
                            let next = match *selected_index.read() {
                                Some(0) | None => count - 1,
                                Some(i) => i - 1,
                            };
                            selected_index.set(Some(next));
                        }
                        Key::Enter => {
                            if let Some(i) = *selected_index.read() {
                                if let Some(network) = networks.read().get(i) {
                                    ssid_input.set(network.ssid.clone());
                                }
                            }
                        }
                        Key::Escape => {
                            selected_index.set(None);
                        }
                        _ => {}
                    }
                },
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
                                let is_selected = *selected_index.read() == Some(network_index);
                                let row_class = if is_connected_network {
                                    "border-b border-border bg-emerald-500/10"
                                } else if is_selected {
                                    "border-b border-border bg-primary/10"
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
                                            Button {
                                                class: ssid_class.to_string(),
                                                variant: ButtonVariant::Ghost,
                                                on_click: move |_| ssid_input.set(ssid_for_click.clone()),
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
