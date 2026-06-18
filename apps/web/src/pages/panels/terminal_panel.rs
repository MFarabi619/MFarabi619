use crate::components::terminal::Terminal;
use dioxus::prelude::*;

#[component]
pub fn TerminalPanel(device_url: Signal<String>) -> Element {
    let ws_url = {
        let url = device_url.read().clone();
        url.replace("http://", "ws://").replace("https://", "wss://") + "/ws/shell"
    };

    rsx! {
        section { class: "panel-shell-strong bg-[#0a0a0c] overflow-hidden pt-3 px-3",
            Terminal {
                id: "terminal-container".to_string(),
                ws_url,
                font_size: 13,
                height_class: "h-[350px]".to_string(),
            }
        }
    }
}
