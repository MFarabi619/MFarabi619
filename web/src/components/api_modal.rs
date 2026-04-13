use dioxus::prelude::*;
use dioxus::hooks::UseResourceState;
use dioxus_primitives::dialog::{DialogContent, DialogRoot, DialogTitle};

#[component]
pub fn ApiModal(
    open: Signal<bool>,
    device_url: Signal<String>,
) -> Element {
    let mut api_data = use_resource(move || {
        let is_open = *open.read();
        let url = device_url.read().clone();
        async move {
            if !is_open { return String::new(); }
            match reqwest::get(format!("{url}/api/cloudevents")).await {
                Ok(response) => match response.text().await {
                    Ok(text) => match serde_json::from_str::<serde_json::Value>(&text) {
                        Ok(json) => serde_json::to_string_pretty(&json).unwrap_or(text),
                        Err(_) => text,
                    },
                    Err(err) => format!("Error: {err}"),
                },
                Err(err) => format!("Error: {err}"),
            }
        }
    });

    let content = api_data.value().read().clone().unwrap_or_default();
    let is_loading = matches!(*api_data.state().read(), UseResourceState::Pending);

    rsx! {
        DialogRoot {
            open: open(),
            on_open_change: move |v: bool| open.set(v),
            class: "fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4",

            DialogContent {
                class: "w-full max-w-3xl bg-card border border-border rounded-lg shadow-2xl flex flex-col max-h-[80vh]",

                div { class: "flex items-center justify-between px-5 py-4 border-b border-border",
                    div {
                        DialogTitle { "CloudEvents API" }
                        p { class: "text-sm text-muted-foreground", "Response from /api/cloudevents" }
                    }
                    button {
                        class: "p-1 rounded hover:bg-muted transition-colors text-muted-foreground",
                        aria_label: "Close",
                        onclick: move |_| open.set(false),
                        lucide_dioxus::X { class: "w-5 h-5" }
                    }
                }

                div { class: "flex-1 overflow-auto p-4",
                    if is_loading {
                        div { class: "flex items-center justify-center py-12",
                            lucide_dioxus::LoaderCircle { class: "w-6 h-6 animate-spin text-muted-foreground" }
                        }
                    } else {
                        pre { class: "text-xs font-mono text-foreground whitespace-pre-wrap break-all leading-relaxed",
                            "{content}"
                        }
                    }
                }

                div { class: "flex items-center gap-2 px-5 py-3 border-t border-border",
                    button {
                        class: "px-3 py-1.5 rounded-lg border border-border text-sm hover:bg-muted/50 transition-colors",
                        onclick: move |_| {
                            let text = api_data.value().read().clone().unwrap_or_default();
                            #[cfg(target_arch = "wasm32")]
                            if let Some(window) = web_sys::window() {
                                let _ = window.navigator().clipboard().write_text(&text);
                            }
                        },
                        "Copy"
                    }
                    button {
                        class: "px-3 py-1.5 rounded-lg border border-border text-sm hover:bg-muted/50 transition-colors",
                        onclick: move |_| api_data.restart(),
                        "Refresh"
                    }
                    div { class: "flex-1" }
                    button {
                        class: "px-3 py-1.5 rounded-lg border border-border text-sm hover:bg-muted/50 transition-colors",
                        onclick: move |_| open.set(false),
                        "Close"
                    }
                }
            }
        }
    }
}
