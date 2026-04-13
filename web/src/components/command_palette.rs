use dioxus::prelude::*;
use dioxus_primitives::dialog::{DialogContent, DialogRoot, DialogTitle};
use lucide_dioxus::{Braces, HardDrive, Radar, RefreshCw, Search, Trash2, Upload, Wifi, Zap};

fn scroll_to_element(id: &str) {
    #[cfg(target_arch = "wasm32")]
    if let Some(el) = web_sys::window()
        .and_then(|w| w.document())
        .and_then(|d| d.get_element_by_id(id))
    {
        use wasm_bindgen::JsCast;
        if let Ok(html_el) = el.dyn_into::<web_sys::HtmlElement>() {
            html_el.scroll_into_view();
        }
    }
}

#[component]
pub fn CommandPalette(
    on_open_api: EventHandler<()>,
    on_sample: EventHandler<()>,
    on_scan_networks: EventHandler<()>,
    on_refresh_files: EventHandler<()>,
    on_upload: EventHandler<()>,
) -> Element {
    let mut open = use_signal(|| false);
    let mut filter_text = use_signal(String::new);

    use_effect(move || {
        if *crate::SHOW_COMMAND_PALETTE.read() {
            open.set(true);
            *crate::SHOW_COMMAND_PALETTE.write() = false;
        }
    });

    let mut close = move || {
        open.set(false);
        filter_text.set(String::new());
    };

    let query = filter_text.read().to_ascii_lowercase();
    let matches = move |keywords: &str| -> bool {
        query.is_empty() || keywords.to_ascii_lowercase().contains(&query)
    };

    rsx! {
        DialogRoot {
            open: open(),
            on_open_change: move |v: bool| {
                if !v { close(); } else { open.set(true); }
            },
            class: "fixed inset-0 z-50 flex items-start justify-center pt-[20vh] bg-black/60 backdrop-blur-sm",

            DialogContent {
                class: "w-full max-w-lg mx-4 rounded-lg border border-border bg-card shadow-2xl overflow-hidden",

                div { class: "flex items-center gap-3 border-b border-border px-4 py-3",
                    Search { class: "w-5 h-5 text-muted-foreground shrink-0" }
                    input {
                        class: "flex-1 bg-transparent text-foreground placeholder:text-muted-foreground outline-none text-sm",
                        r#type: "text",
                        aria_label: "Search commands",
                        placeholder: "Type a command or search...",
                        value: "{filter_text}",
                        oninput: move |e| filter_text.set(e.value()),
                        onmounted: move |e| async move { let _ = e.set_focus(true).await; },
                    }
                    button {
                        class: "p-1 rounded hover:bg-muted transition-colors text-muted-foreground",
                        aria_label: "Close",
                        onclick: move |_| close(),
                        lucide_dioxus::X { class: "w-4 h-4" }
                    }
                }

                DialogTitle { class: "sr-only", "Command Palette" }

                div { class: "max-h-[400px] overflow-y-auto p-2",

                    if matches("sample voltage current temperature sensor") || matches("api cloudevents json") || matches("upload file sd") || matches("scan networks") || matches("refresh filesystem") || matches("clear cache") {
                        h3 { class: "px-2 py-1.5 text-xs text-muted-foreground uppercase tracking-wider", "Actions" }
                    }

                    if matches("sample voltage current temperature sensor") {
                        CmdItem {
                            icon: rsx! { lucide_dioxus::FlaskConical { class: "w-4 h-4" } },
                            label: "Sample Sensors",
                            shortcut: "Ctrl+Enter",
                            on_click: move |_| { on_sample.call(()); close(); },
                        }
                    }
                    if matches("api cloudevents json response") {
                        CmdItem {
                            icon: rsx! { Braces { class: "w-4 h-4" } },
                            label: "Open API",
                            shortcut: "Ctrl+/",
                            on_click: move |_| { on_open_api.call(()); close(); },
                        }
                    }
                    if matches("upload file sd card") {
                        CmdItem {
                            icon: rsx! { Upload { class: "w-4 h-4" } },
                            label: "Upload File to SD",
                            on_click: move |_| { on_upload.call(()); close(); },
                        }
                    }
                    if matches("scan networks wifi") {
                        CmdItem {
                            icon: rsx! { Radar { class: "w-4 h-4" } },
                            label: "Scan Networks",
                            on_click: move |_| { on_scan_networks.call(()); close(); },
                        }
                    }
                    if matches("refresh filesystem files sd littlefs") {
                        CmdItem {
                            icon: rsx! { RefreshCw { class: "w-4 h-4" } },
                            label: "Refresh Filesystems",
                            on_click: move |_| { on_refresh_files.call(()); close(); },
                        }
                    }
                    if matches("clear cache reset storage reload") {
                        CmdItem {
                            icon: rsx! { Trash2 { class: "w-4 h-4" } },
                            label: "Clear Cache & Reload",
                            on_click: move |_| {
                                #[cfg(target_arch = "wasm32")]
                                if let Some(storage) = web_sys::window()
                                    .and_then(|w| w.local_storage().ok().flatten())
                                { storage.clear().ok(); }
                                document::eval("location.reload()");
                                close();
                            },
                        }
                    }

                    if matches("measurements sensor terminal network filesystem flash") {
                        hr { class: "my-1 border-border" }
                        h3 { class: "px-2 py-1.5 text-xs text-muted-foreground uppercase tracking-wider", "Navigate" }
                    }

                    if matches("measurements sensor cloudevents voltage temperature co2") {
                        CmdItem {
                            icon: rsx! { Zap { class: "w-4 h-4" } },
                            label: "Measurements",
                            on_click: move |_| { scroll_to_element("cloudevents-section"); close(); },
                        }
                    }
                    if matches("terminal shell console") {
                        CmdItem {
                            icon: rsx! { lucide_dioxus::Terminal { class: "w-4 h-4" } },
                            label: "Terminal",
                            on_click: move |_| { scroll_to_element("terminal-container"); close(); },
                        }
                    }
                    if matches("network wifi ssid connect") {
                        CmdItem {
                            icon: rsx! { Wifi { class: "w-4 h-4" } },
                            label: "Network",
                            on_click: move |_| { scroll_to_element("network-section"); close(); },
                        }
                    }
                    if matches("filesystem sd card files littlefs") {
                        CmdItem {
                            icon: rsx! { HardDrive { class: "w-4 h-4" } },
                            label: "Filesystem",
                            on_click: move |_| { scroll_to_element("filesystem-section"); close(); },
                        }
                    }
                    if matches("flash firmware serial esptool") {
                        CmdItem {
                            icon: rsx! { lucide_dioxus::Cpu { class: "w-4 h-4" } },
                            label: "Firmware Flash",
                            on_click: move |_| { scroll_to_element("flash-panel"); close(); },
                        }
                    }
                }
            }
        }
    }
}

#[component]
fn CmdItem(
    icon: Element,
    label: &'static str,
    shortcut: Option<&'static str>,
    on_click: EventHandler<()>,
) -> Element {
    rsx! {
        button {
            class: "flex w-full items-center gap-3 rounded-lg px-3 py-2 text-sm text-foreground hover:bg-muted/50 transition-colors",
            onclick: move |_| on_click.call(()),
            span { class: "text-primary", {icon} }
            span { "{label}" }
            if let Some(kbd) = shortcut {
                span { class: "ml-auto text-xs text-muted-foreground bg-muted px-1.5 py-0.5 rounded", "{kbd}" }
            }
        }
    }
}
