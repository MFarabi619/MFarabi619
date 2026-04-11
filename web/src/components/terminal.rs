use dioxus::prelude::*;

#[component]
pub fn Terminal(
    id: String,
    ws_url: String,
    #[props(default = 13)] font_size: u8,
    #[props(default = "h-[350px]".to_string())] height_class: String,
) -> Element {
    let mut initialized = use_signal(|| false);
    let id_clone = id.clone();
    let id_for_cleanup = id.clone();

    use_drop(move || {
        document::eval(&format!(
            r#"
            const el = document.getElementById('{id_for_cleanup}');
            if (el && el.__ws) {{ try {{ el.__ws.close(); }} catch(e) {{}} }}
            if (el && el.__term) {{ try {{ el.__term.dispose(); }} catch(e) {{}} }}
            "#
        ));
    });

    use_effect(move || {
        if *initialized.peek() { return; }
        initialized.set(true);

        let id = id_clone.clone();
        let ws_url = ws_url.clone();
        let font_size = font_size;

        document::eval(&format!(r#"
            (function tryInit() {{
                if (typeof Terminal === 'undefined' || typeof FitAddon === 'undefined') {{
                    setTimeout(tryInit, 200);
                    return;
                }}
                const container = document.getElementById('{id}');
                if (!container) {{ setTimeout(tryInit, 200); return; }}
                if (container.dataset.initialized) return;
                container.dataset.initialized = 'true';
                container.innerHTML = '';

                const term = new Terminal({{
                    cursorBlink: true,
                    fontSize: {font_size},
                    fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
                    theme: window.CERATINA_THEME || {{}}
                }});

                const fit = new FitAddon.FitAddon();
                term.loadAddon(fit);
                if (typeof WebglAddon !== 'undefined') {{
                    try {{
                        const webgl = new WebglAddon.WebglAddon();
                        webgl.onContextLoss(() => webgl.dispose());
                        term.loadAddon(webgl);
                    }} catch(e) {{}}
                }}
                if (typeof WebLinksAddon !== 'undefined') {{
                    term.loadAddon(new WebLinksAddon.WebLinksAddon());
                }}

                term.open(container);
                fit.fit();
                container.__term = term;

                const ro = new ResizeObserver(() => {{ try {{ fit.fit(); }} catch(e) {{}} }});
                ro.observe(container);

                let ws = null;

                function connect() {{
                    if (ws && ws.readyState <= 1) return;
                    ws = new WebSocket('{ws_url}');
                    container.__ws = ws;

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
        div {
            id: "{id}",
            class: "w-full {height_class}",
            div { class: "p-4 space-y-3 animate-pulse",
                div { class: "h-4 w-3/4 bg-muted/30 rounded" }
                div { class: "h-4 w-1/2 bg-muted/30 rounded" }
                div { class: "h-4 w-2/3 bg-muted/30 rounded" }
            }
        }
    }
}
