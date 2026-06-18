use crate::api::DEFAULT_DEVICE_URL;
use crate::components::terminal::Terminal;
use dioxus::prelude::*;

#[component]
pub fn Shell() -> Element {
    let device_url = use_signal(|| {
        #[cfg(target_arch = "wasm32")]
        {
            web_sys::window()
                .and_then(|w| w.local_storage().ok().flatten())
                .and_then(|s| s.get_item("device_url").ok().flatten())
                .unwrap_or_else(|| DEFAULT_DEVICE_URL.to_string())
        }
        #[cfg(not(target_arch = "wasm32"))]
        DEFAULT_DEVICE_URL.to_string()
    });

    let ws_url = {
        let url = device_url.read().clone();
        url.replace("http://", "ws://").replace("https://", "wss://") + "/ws/shell"
    };

    rsx! {
        document::Title { "Apidae Shell" }
        div { class: "fixed inset-0 bg-[#0a0a0c]",
            Terminal {
                id: "shell-fullscreen".to_string(),
                ws_url,
                font_size: 14,
                height_class: "h-full".to_string(),
            }
        }
    }
}
