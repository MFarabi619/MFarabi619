use dioxus::prelude::*;

#[component]
pub fn TerminalPanel(device_url: Signal<String>) -> Element {
    let mut initialized = use_signal(|| false);

    use_effect(move || {
        if *initialized.peek() { return; }
        initialized.set(true);

        let url = device_url.read().clone();
        let ws_url = url.replace("http://", "ws://").replace("https://", "wss://");
        let ws_url = format!("{ws_url}/ws/shell");

        document::eval(&format!(r#"
            (function tryInit() {{
                if (typeof Terminal === 'undefined' || typeof FitAddon === 'undefined') {{
                    setTimeout(tryInit, 200);
                    return;
                }}
                const container = document.getElementById('terminal-container');
                if (!container) {{ setTimeout(tryInit, 200); return; }}
                if (container.dataset.initialized) return;
                container.dataset.initialized = 'true';
                container.innerHTML = '';

                const term = new Terminal({{
                    cursorBlink: true,
                    fontSize: 13,
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

                    ws.onopen = () => {{
                        term.write('\x1b[32m[connected]\x1b[0m\r\n');
                    }};

                    ws.onmessage = (e) => {{
                        term.write(e.data);
                    }};

                    ws.onclose = () => {{
                        term.write('\r\n\x1b[31m[disconnected]\x1b[0m\r\n');
                        setTimeout(connect, 3000);
                    }};

                    ws.onerror = () => {{}};
                }}

                term.onData((data) => {{
                    if (ws && ws.readyState === WebSocket.OPEN) {{
                        ws.send(data);
                    }}
                }});

                connect();
            }})();
        "#));
    });

    rsx! {
        section { class: "panel-shell-strong bg-[#0a0a0c] overflow-hidden pt-3 px-3",
            div {
                id: "terminal-container",
                class: "h-[350px] w-full",
                div { class: "p-4 space-y-3 animate-pulse",
                    div { class: "h-4 w-3/4 bg-muted/30 rounded" }
                    div { class: "h-4 w-1/2 bg-muted/30 rounded" }
                    div { class: "h-4 w-2/3 bg-muted/30 rounded" }
                    div { class: "h-4 w-1/3 bg-muted/30 rounded" }
                }
            }
        }
    }
}
