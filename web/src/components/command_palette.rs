use dioxus::prelude::*;
use lucide_dioxus::{Braces, HardDrive, Radar, RefreshCw, Search, Wifi, Zap};

fn scroll_to_element(id: &str) {
    if let Some(el) = web_sys::window()
        .and_then(|w| w.document())
        .and_then(|d| d.get_element_by_id(id))
    {
        let mut opts = web_sys::ScrollIntoViewOptions::new();
        opts.behavior(web_sys::ScrollBehavior::Smooth);
        el.scroll_into_view_with_scroll_into_view_options(&opts);
    }
}

#[component]
pub fn CommandPalette(
    on_open_api: EventHandler<()>,
    on_scan_networks: EventHandler<()>,
    on_refresh_files: EventHandler<()>,
) -> Element {
    let mut open = use_signal(|| false);
    let mut filter_text = use_signal(String::new);

    // Sync with global signal via effect (not during render)
    use_effect(move || {
        if *crate::SHOW_COMMAND_PALETTE.read() {
            open.set(true);
            *crate::SHOW_COMMAND_PALETTE.write() = false;
        }
    });

    if !*open.read() {
        return rsx! {};
    }

    let mut close = move || {
        open.set(false);
        filter_text.set(String::new());
    };

    let query = filter_text.read().to_ascii_lowercase();
    let matches = move |keywords: &str| -> bool {
        query.is_empty() || keywords.to_ascii_lowercase().contains(&query)
    };

    rsx! {
        div {
            class: "fixed inset-0 z-50 flex items-start justify-center pt-[20vh] bg-black/60 backdrop-blur-sm",
            onclick: move |_| close(),
            div {
                class: "w-full max-w-lg mx-4 rounded-2xl border border-border bg-card shadow-2xl overflow-hidden",
                onclick: move |e| e.stop_propagation(),

                // Search input
                div { class: "flex items-center gap-3 border-b border-border px-4 py-3",
                    Search { class: "w-5 h-5 text-muted-foreground shrink-0" }
                    input {
                        class: "flex-1 bg-transparent text-foreground placeholder:text-muted-foreground outline-none text-sm",
                        r#type: "text",
                        placeholder: "Type a command or search...",
                        value: "{filter_text}",
                        oninput: move |e| filter_text.set(e.value()),
                        onmounted: move |e| async move {
                            let _ = e.set_focus(true).await;
                        },
                        onkeydown: move |e| {
                            if e.key() == Key::Escape {
                                close();
                            }
                        },
                    }
                    button {
                        class: "p-1 rounded hover:bg-muted transition-colors text-muted-foreground",
                        onclick: move |_| close(),
                        lucide_dioxus::X { class: "w-4 h-4" }
                    }
                }

                // Results
                div { class: "max-h-[300px] overflow-y-auto p-2",

                    // Actions group
                    if matches("api cloudevents json") || matches("scan networks wifi") || matches("refresh filesystem files") {
                        div { class: "px-2 py-1.5 text-xs text-muted-foreground uppercase tracking-wider", "Actions" }
                    }

                    if matches("api cloudevents json ctrl slash") {
                        CmdItem {
                            icon: rsx! { Braces { class: "w-4 h-4" } },
                            label: "Open API",
                            shortcut: "Ctrl+/",
                            on_click: move |_| { on_open_api.call(()); close(); },
                        }
                    }
                    if matches("scan networks wifi") {
                        CmdItem {
                            icon: rsx! { Radar { class: "w-4 h-4" } },
                            label: "Scan Networks",
                            on_click: move |_| { on_scan_networks.call(()); close(); },
                        }
                    }
                    if matches("refresh filesystem files sd") {
                        CmdItem {
                            icon: rsx! { RefreshCw { class: "w-4 h-4" } },
                            label: "Refresh Filesystems",
                            on_click: move |_| { on_refresh_files.call(()); close(); },
                        }
                    }

                    // Navigate group
                    if matches("cloudevents measurements sensor") || matches("networking wifi") || matches("filesystem sd card") {
                        hr { class: "my-1 border-border" }
                        div { class: "px-2 py-1.5 text-xs text-muted-foreground uppercase tracking-wider", "Navigate" }
                    }

                    if matches("cloudevents measurements sensor") {
                        CmdItem {
                            icon: rsx! { Zap { class: "w-4 h-4" } },
                            label: "CloudEvents",
                            on_click: move |_| {
                                scroll_to_element("cloudevents-section");
                                close();
                            },
                        }
                    }
                    if matches("networking wifi ssid connect") {
                        CmdItem {
                            icon: rsx! { Wifi { class: "w-4 h-4" } },
                            label: "Network",
                            on_click: move |_| {
                                scroll_to_element("network-section");
                                close();
                            },
                        }
                    }
                    if matches("filesystem sd card files") {
                        CmdItem {
                            icon: rsx! { HardDrive { class: "w-4 h-4" } },
                            label: "Filesystem",
                            on_click: move |_| {
                                scroll_to_element("filesystem-section");
                                close();
                            },
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
                span { class: "ml-auto text-xs text-muted-foreground bg-transparent tracking-widest", "{kbd}" }
            }
        }
    }
}
