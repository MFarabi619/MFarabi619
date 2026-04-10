use dioxus::prelude::*;
use wasm_bindgen::JsCast;

#[component]
pub fn ApiModal(
    open: Signal<bool>,
    device_url: Signal<String>,
) -> Element {
    let mut content = use_signal(|| "Loading...".to_string());
    let mut loading = use_signal(|| false);

    let mut fetch_api = move || {
        loading.set(true);
        let url = device_url.read().clone();
        spawn(async move {
            match reqwest::get(format!("{url}/api/cloudevents")).await {
                Ok(response) => {
                    match response.text().await {
                        Ok(text) => {
                            let formatted = match serde_json::from_str::<serde_json::Value>(&text) {
                                Ok(json) => serde_json::to_string_pretty(&json).unwrap_or(text),
                                Err(_) => text,
                            };
                            content.set(formatted);
                        }
                        Err(err) => content.set(format!("Error: {err}")),
                    }
                }
                Err(err) => content.set(format!("Error: {err}")),
            }
            loading.set(false);
        });
    };

    use_effect(move || {
        if *open.read() {
            fetch_api();
        }
    });

    if !*open.read() {
        return rsx! {};
    }

    let mut close = move || open.set(false);

    rsx! {
        div {
            class: "fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4",
            onclick: move |_| close(),
            div {
                class: "w-full max-w-3xl bg-card border border-border rounded-lg shadow-2xl flex flex-col max-h-[80vh]",
                onclick: move |e| e.stop_propagation(),

                div { class: "flex items-center justify-between px-5 py-4 border-b border-border",
                    div {
                        h2 { class: "text-lg font-semibold", "CloudEvents API" }
                        p { class: "text-sm text-muted-foreground", "Response from /api/cloudevents" }
                    }
                    button {
                        class: "p-1 rounded hover:bg-muted transition-colors text-muted-foreground",
                        onclick: move |_| close(),
                        lucide_dioxus::X { class: "w-5 h-5" }
                    }
                }

                div { class: "flex-1 overflow-auto p-4",
                    if *loading.read() {
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
                            let text = content.read().clone();
                            if let Some(window) = web_sys::window() {
                                let _ = window.navigator().clipboard().write_text(&text);
                            }
                        },
                        "Copy"
                    }
                    button {
                        class: "px-3 py-1.5 rounded-lg border border-border text-sm hover:bg-muted/50 transition-colors",
                        onclick: move |_| fetch_api(),
                        "Refresh"
                    }
                    div { class: "flex-1" }
                    button {
                        class: "px-3 py-1.5 rounded-lg border border-border text-sm hover:bg-muted/50 transition-colors",
                        onclick: move |_| close(),
                        "Close"
                    }
                }
            }
        }
    }
}
