use crate::api::DEFAULT_DEVICE_URL;
use dioxus::prelude::*;

#[component]
pub fn Shell() -> Element {
    let mut initialized = use_signal(|| false);

    let device_url = use_signal(|| {
        #[cfg(target_arch = "wasm32")]
        {
            web_sys::window()
                .and_then(|w| w.local_storage().ok().flatten())
                .and_then(|s| s.get_item("device_url").ok().flatten())
                .unwrap_or_else(|| DEFAULT_DEVICE_URL.to_string())
        }
        #[cfg(not(target_arch = "wasm32"))]
        { DEFAULT_DEVICE_URL.to_string() }
    });

    use_effect(move || {
        if *initialized.peek() { return; }
        initialized.set(true);

        let url = device_url.read().clone();
        let ws_url = url.replace("http://", "ws://").replace("https://", "wss://");
        let ws_url = format!("{ws_url}/ws/shell");

        document::eval(&format!(r#"
            setTimeout(function() {{
                const container = document.getElementById('shell-fullscreen');
                if (!container || container.dataset.initialized) return;
                container.dataset.initialized = 'true';

                const term = new Terminal({{
                    cursorBlink: true,
                    fontSize: 14,
                    fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
                    theme: {{
                        background: '#0a0a0c',
                        foreground: '#d4a84b',
                        cursor: '#f5b72b',
                        selectionBackground: 'rgba(245, 183, 43, 0.3)',
                        black: '#0a0a0c',
                        red: '#e06c6c',
                        green: '#6cc070',
                        yellow: '#f5b72b',
                        blue: '#6c9ee0',
                        magenta: '#c06cc0',
                        cyan: '#6cc0c0',
                        white: '#d4a84b'
                    }}
                }});

                const fit = new FitAddon.FitAddon();
                term.loadAddon(fit);
                term.open(container);
                fit.fit();

                window.addEventListener('resize', () => fit.fit());

                let ws = null;

                function connect() {{
                    if (ws && ws.readyState <= 1) return;
                    ws = new WebSocket('{ws_url}');
                    ws.onopen = () => term.write('\x1b[32m[connected]\x1b[0m\r\n');
                    ws.onmessage = (e) => term.write(e.data);
                    ws.onclose = () => {{
                        term.write('\r\n\x1b[31m[disconnected]\x1b[0m\r\n');
                        setTimeout(connect, 3000);
                    }};
                    ws.onerror = () => {{}};
                }}

                term.onData((data) => {{
                    if (ws && ws.readyState === WebSocket.OPEN) ws.send(data);
                }});

                connect();
            }}, 100);
        "#));
    });

    rsx! {
        div {
            id: "shell-fullscreen",
            class: "fixed inset-0 bg-[#0a0a0c] p-2",
        }
    }
}
