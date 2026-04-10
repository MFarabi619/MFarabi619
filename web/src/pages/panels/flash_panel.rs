use dioxus::prelude::*;
use dioxus::document::Eval;
use serde::Deserialize;
use ui::components::switch::Switch;
use ui::components::toast::use_toast;

// ─────────────────────────────────────────────────────────────────────────────
//  Types
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Clone, Debug)]
struct LogEntry {
    msg: String,
    level: LogLevel,
}

#[derive(Clone, Debug)]
enum LogLevel {
    Ok,
    Warn,
    Err,
    Dim,
    Default,
}

impl LogLevel {
    fn color_class(&self) -> &'static str {
        match self {
            LogLevel::Ok => "text-[#6cc070]",
            LogLevel::Warn => "text-[#f5b72b]",
            LogLevel::Err => "text-[#e06c6c]",
            LogLevel::Dim => "text-[#a67b2f]",
            LogLevel::Default => "text-[#d4a84b]",
        }
    }
}

#[derive(Deserialize, Debug)]
struct JsMessage {
    r#type: String,
    #[serde(default)]
    chip: String,
    #[serde(default)]
    msg: String,
    #[serde(default)]
    level: String,
    #[serde(default)]
    percent: u8,
    #[serde(default)]
    name: String,
    #[serde(default)]
    size: usize,
}

// ─────────────────────────────────────────────────────────────────────────────
//  JS Snippets
// ─────────────────────────────────────────────────────────────────────────────

const JS_INIT_TERMINAL: &str = r#"
(function() {
    if (typeof Terminal === 'undefined') return;
    const el = document.getElementById('flash-monitor-term');
    if (!el || el.dataset.initialized) return;
    el.dataset.initialized = 'true';

    const term = new Terminal({
        cursorBlink: true, fontSize: 12,
        fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
        theme: window.CERATINA_THEME || {}
    });

    const fit = new FitAddon.FitAddon();
    term.loadAddon(fit);
    if (typeof WebglAddon !== 'undefined') {
        try {
            const webgl = new WebglAddon.WebglAddon();
            webgl.onContextLoss(() => webgl.dispose());
            term.loadAddon(webgl);
        } catch(e) {}
    }
    if (typeof WebLinksAddon !== 'undefined') {
        term.loadAddon(new WebLinksAddon.WebLinksAddon());
    }

    term.open(el);
    fit.fit();

    const ro = new ResizeObserver(() => { try { fit.fit(); } catch(e) {} });
    ro.observe(el);

    window.__flashTerm = term;
    window.__flashFit = fit;
})();
"#;

const JS_CONNECT: &str = r#"
(async function() {
    if (!navigator.serial) {
        dioxus.send(JSON.stringify({type:'log', msg:'Web Serial not supported. Use Chrome/Edge.', level:'err'}));
        return 'error';
    }
    try {
        const port = await navigator.serial.requestPort();
        window.__flashPort = port;

        dioxus.send(JSON.stringify({type:'log', msg:'Loading esptool...', level:'dim'}));
        const { ESPLoader, Transport } = await import('https://unpkg.com/esptool-js/bundle.js');
        window.__ESPLoader = ESPLoader;
        window.__Transport = Transport;

        const transport = new Transport(port, true);
        window.__flashTransport = transport;

        const baud = parseInt(window.__flashBaud || '921600') || 921600;
        const loader = new ESPLoader({
            transport, baudrate: baud, romBaudrate: 115200,
            terminal: {
                clean() {},
                writeLine(d) { dioxus.send(JSON.stringify({type:'log', msg:d, level:'default'})); },
                write(d) { dioxus.send(JSON.stringify({type:'log', msg:d, level:'default'})); }
            }
        });
        window.__flashLoader = loader;

        dioxus.send(JSON.stringify({type:'log', msg:'Connecting at ' + baud + '...', level:'warn'}));
        const chip = await loader.main();
        dioxus.send(JSON.stringify({type:'log', msg:'Connected: ' + chip, level:'ok'}));
        dioxus.send(JSON.stringify({type:'connected', chip: chip}));

        // Disconnect transport to release port for monitor
        await transport.disconnect();
        window.__flashTransport = null;
        window.__flashLoader = null;

        return 'ok';
    } catch(err) {
        dioxus.send(JSON.stringify({type:'log', msg:'Connect failed: ' + err.message, level:'err'}));
        window.__flashPort = null;
        window.__flashTransport = null;
        window.__flashLoader = null;
        return 'error';
    }
})()
"#;

const JS_MONITOR_START: &str = r#"
(async function() {
    const port = window.__flashPort;
    if (!port) { dioxus.send(JSON.stringify({type:'log', msg:'No port available', level:'err'})); return; }

    window.__monitorStop = false;
    const baud = parseInt(window.__flashBaud || '115200') || 115200;

    try {
        if (!port.readable) {
            await port.open({ baudRate: baud });
        }

        const { Transport } = await import('https://unpkg.com/esptool-js/bundle.js');
        const transport = new Transport(port, true);
        window.__monitorTransport = transport;
        await transport.connect(baud);

        const term = window.__flashTerm;

        dioxus.send(JSON.stringify({type:'log', msg:'Monitor started at ' + baud + ' baud', level:'ok'}));
        dioxus.send(JSON.stringify({type:'monitor_started'}));

        // User input → device
        if (term) {
            window.__monitorTermHandler = term.onData(function(data) {
                const writer = port.writable.getWriter();
                writer.write(new TextEncoder().encode(data));
                writer.releaseLock();
            });
        }

        // Device → terminal (rawRead)
        await transport.rawRead(
            function(value) {
                if (term) term.write(value);
            },
            function() { return window.__monitorStop === true; }
        );
    } catch(err) {
        if (!window.__monitorStop) {
            dioxus.send(JSON.stringify({type:'log', msg:'Monitor error: ' + err.message, level:'err'}));
        }
    }

    // Cleanup
    try {
        if (window.__monitorTermHandler) { window.__monitorTermHandler.dispose(); window.__monitorTermHandler = null; }
        if (window.__monitorTransport) { await window.__monitorTransport.disconnect(); window.__monitorTransport = null; }
    } catch(e) {}

    dioxus.send(JSON.stringify({type:'monitor_stopped'}));
})()
"#;

const JS_MONITOR_STOP: &str = r#"
window.__monitorStop = true;
"#;

const JS_FLASH: &str = r#"
(async function() {
    const port = window.__flashPort;
    if (!port) return 'no_port';

    // Stop monitor first
    window.__monitorStop = true;
    await new Promise(r => setTimeout(r, 500));
    try { if (window.__monitorTransport) await window.__monitorTransport.disconnect(); } catch(e) {}
    window.__monitorTransport = null;

    try {
        // Reopen port for esptool
        if (!port.readable) {
            const baud = parseInt(window.__flashBaud || '921600') || 921600;
            await port.open({ baudRate: baud });
        }

        const Transport = window.__Transport;
        const ESPLoader = window.__ESPLoader;
        const transport = new Transport(port, true);
        const baud = parseInt(window.__flashBaud || '921600') || 921600;

        const loader = new ESPLoader({
            transport, baudrate: baud, romBaudrate: 115200,
            terminal: {
                clean() {},
                writeLine(d) { dioxus.send(JSON.stringify({type:'log', msg:d, level:'default'})); },
                write(d) { dioxus.send(JSON.stringify({type:'log', msg:d, level:'default'})); }
            }
        });

        dioxus.send(JSON.stringify({type:'log', msg:'Reconnecting for flash...', level:'warn'}));
        await loader.main();

        // Read config from window globals
        const flashMode = window.__flashMode || 'keep';
        const flashFreq = window.__flashFreq || 'keep';
        const flashSize = window.__flashSize || 'keep';
        const compress = window.__flashCompress !== false;
        const eraseAll = window.__flashEraseAll === true;
        const ssid = (window.__flashWifiSsid || '').trim();
        const pass = window.__flashWifiPass || '';

        // Build file array
        let fileArray;
        const fw = window.__flashFirmwareData;
        const multi = window.__flashMultiFiles;

        if (multi) {
            fileArray = multi.map(f => ({ data: new Uint8Array(f.data), address: f.address }));
            if (ssid) {
                patchSentinel(fileArray[2].data, '@@WIFI_SSID@@', ssid, 33);
                patchSentinel(fileArray[2].data, '@@WIFI_PASS@@', pass, 65);
                dioxus.send(JSON.stringify({type:'log', msg:'Embedded WiFi: ' + ssid, level:'ok'}));
            }
            dioxus.send(JSON.stringify({type:'log', msg:'Flashing 3 files (bootloader + partitions + app)...', level:'warn'}));
        } else {
            const addr = parseInt(window.__flashAddr || '0x10000', 16) || 0x10000;
            const dataToFlash = new Uint8Array(fw);
            if (ssid) {
                patchSentinel(dataToFlash, '@@WIFI_SSID@@', ssid, 33);
                patchSentinel(dataToFlash, '@@WIFI_PASS@@', pass, 65);
                dioxus.send(JSON.stringify({type:'log', msg:'Embedded WiFi: ' + ssid, level:'ok'}));
            }
            fileArray = [{ data: dataToFlash, address: addr }];
            dioxus.send(JSON.stringify({type:'log', msg:'Flashing to 0x' + addr.toString(16) + '...', level:'warn'}));
        }

        await loader.writeFlash({
            fileArray, flashSize: flashSize, flashMode: flashMode,
            flashFreq: flashFreq, eraseAll, compress,
            reportProgress(fi, written, total) {
                dioxus.send(JSON.stringify({type:'progress', percent: Math.round((written/total)*100)}));
            }
        });

        dioxus.send(JSON.stringify({type:'progress', percent: 100}));
        dioxus.send(JSON.stringify({type:'log', msg:'Flash complete!', level:'ok'}));

        try { await loader.after('hard_reset'); } catch(e) {
            try { await transport.setDTR(false); await transport.setRTS(true); await new Promise(r=>setTimeout(r,100)); await transport.setRTS(false); } catch(e2){}
        }
        dioxus.send(JSON.stringify({type:'log', msg:'Device reset.', level:'ok'}));

        await transport.disconnect();
        return 'ok';
    } catch(err) {
        dioxus.send(JSON.stringify({type:'log', msg:'Flash error: ' + err.message, level:'err'}));
        return 'error';
    }

    function patchSentinel(data, sentinel, value, slotSize) {
        const enc = new TextEncoder();
        const needle = enc.encode(sentinel);
        for (let i = 0; i <= data.length - needle.length; i++) {
            let match = true;
            for (let j = 0; j < needle.length; j++) { if (data[i+j] !== needle[j]) { match = false; break; } }
            if (match) {
                const rep = enc.encode(value);
                for (let k = 0; k < slotSize; k++) data[i+k] = k < rep.length ? rep[k] : 0;
                return true;
            }
        }
        return false;
    }
})()
"#;

const JS_FETCH_FIRMWARE: &str = r#"
(async function() {
    const val = window.__flashBundledSelection;
    if (!val) return;

    if (val === 'all') {
        try {
            dioxus.send(JSON.stringify({type:'log', msg:'Fetching all firmware files...', level:'warn'}));
            const [bl, pt, fw] = await Promise.all([
                fetch('/assets/bootloader.bin').then(r => r.arrayBuffer()),
                fetch('/assets/partitions.bin').then(r => r.arrayBuffer()),
                fetch('/assets/firmware.bin').then(r => r.arrayBuffer())
            ]);
            window.__flashMultiFiles = [
                { data: new Uint8Array(bl), address: 0x0 },
                { data: new Uint8Array(pt), address: 0x8000 },
                { data: new Uint8Array(fw), address: 0x10000 }
            ];
            window.__flashFirmwareData = window.__flashMultiFiles[2].data;
            const totalKb = ((bl.byteLength + pt.byteLength + fw.byteLength) / 1024).toFixed(1);
            dioxus.send(JSON.stringify({type:'firmware_loaded', name:'all', size: bl.byteLength + pt.byteLength + fw.byteLength}));
            dioxus.send(JSON.stringify({type:'log', msg:'Loaded: bootloader (' + (bl.byteLength/1024).toFixed(1) + ' KB) + partitions (' + (pt.byteLength/1024).toFixed(1) + ' KB) + firmware (' + (fw.byteLength/1024).toFixed(1) + ' KB)', level:'ok'}));
        } catch(err) {
            dioxus.send(JSON.stringify({type:'log', msg:'Failed to fetch: ' + err.message, level:'err'}));
        }
        return;
    }

    try {
        dioxus.send(JSON.stringify({type:'log', msg:'Fetching ' + val + '...', level:'warn'}));
        const resp = await fetch(val);
        const buf = await resp.arrayBuffer();
        window.__flashFirmwareData = new Uint8Array(buf);
        window.__flashMultiFiles = null;
        const name = val.split('/').pop();
        dioxus.send(JSON.stringify({type:'firmware_loaded', name: name, size: buf.byteLength}));
        dioxus.send(JSON.stringify({type:'log', msg:'Loaded: ' + name + ' (' + (buf.byteLength/1024).toFixed(1) + ' KB)', level:'ok'}));
    } catch(err) {
        dioxus.send(JSON.stringify({type:'log', msg:'Failed to fetch: ' + err.message, level:'err'}));
    }
})()
"#;

const JS_DISCONNECT: &str = r#"
(async function() {
    window.__monitorStop = true;
    await new Promise(r => setTimeout(r, 300));
    try { if (window.__monitorTransport) await window.__monitorTransport.disconnect(); } catch(e) {}
    try { if (window.__flashTransport) await window.__flashTransport.disconnect(); } catch(e) {}
    try { if (window.__flashPort && window.__flashPort.readable) await window.__flashPort.close(); } catch(e) {}
    window.__monitorTransport = null;
    window.__flashTransport = null;
    window.__flashLoader = null;
    window.__flashPort = null;
    window.__flashFirmwareData = null;
    window.__flashMultiFiles = null;
    dioxus.send(JSON.stringify({type:'log', msg:'Disconnected', level:'dim'}));
})()
"#;

const JS_ERASE: &str = r#"
(async function() {
    const port = window.__flashPort;
    if (!port) return;

    window.__monitorStop = true;
    await new Promise(r => setTimeout(r, 500));
    try { if (window.__monitorTransport) await window.__monitorTransport.disconnect(); } catch(e) {}
    window.__monitorTransport = null;

    try {
        if (!port.readable) await port.open({ baudRate: parseInt(window.__flashBaud || '921600') || 921600 });
        const Transport = window.__Transport;
        const ESPLoader = window.__ESPLoader;
        const transport = new Transport(port, true);
        const loader = new ESPLoader({
            transport, baudrate: parseInt(window.__flashBaud || '921600') || 921600, romBaudrate: 115200,
            terminal: { clean(){}, writeLine(d){ dioxus.send(JSON.stringify({type:'log', msg:d, level:'default'})); }, write(d){ dioxus.send(JSON.stringify({type:'log', msg:d, level:'default'})); } }
        });
        await loader.main();
        dioxus.send(JSON.stringify({type:'log', msg:'Erasing flash...', level:'warn'}));
        await loader.eraseFlash();
        dioxus.send(JSON.stringify({type:'log', msg:'Erased.', level:'ok'}));
        await transport.disconnect();
    } catch(err) {
        dioxus.send(JSON.stringify({type:'log', msg:'Erase error: ' + err.message, level:'err'}));
    }
    return 'done';
})()
"#;

const JS_RESET: &str = r#"
(async function() {
    const port = window.__flashPort;
    if (!port) return;

    window.__monitorStop = true;
    await new Promise(r => setTimeout(r, 500));
    try { if (window.__monitorTransport) await window.__monitorTransport.disconnect(); } catch(e) {}

    try {
        if (!port.readable) await port.open({ baudRate: parseInt(window.__flashBaud || '921600') || 921600 });
        const transport = new window.__Transport(port, true);
        const loader = new window.__ESPLoader({
            transport, baudrate: parseInt(window.__flashBaud || '921600') || 921600, romBaudrate: 115200,
            terminal: { clean(){}, writeLine(){}, write(){} }
        });
        await loader.main();
        try { await loader.after('hard_reset'); } catch(e) {
            try { await transport.setDTR(false); await transport.setRTS(true); await new Promise(r=>setTimeout(r,100)); await transport.setRTS(false); } catch(e2){}
        }
        dioxus.send(JSON.stringify({type:'log', msg:'Hard reset.', level:'ok'}));
        await transport.disconnect();
    } catch(err) {
        dioxus.send(JSON.stringify({type:'log', msg:'Reset error: ' + err.message, level:'err'}));
    }
    return 'done';
})()
"#;

// ─────────────────────────────────────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────────────────────────────────────

fn sync_config_to_js(baud: &str, mode: &str, freq: &str, size: &str, addr: &str, compress: bool, erase: bool, ssid: &str, pass: &str) {
    document::eval(&format!(
        r#"window.__flashBaud='{}';window.__flashMode='{}';window.__flashFreq='{}';window.__flashSize='{}';window.__flashAddr='{}';window.__flashCompress={};window.__flashEraseAll={};window.__flashWifiSsid='{}';window.__flashWifiPass='{}';"#,
        baud, mode, freq, size, addr, compress, erase, ssid, pass
    ));
}

async fn process_js_messages(
    eval: &mut Eval,
    mut log_entries: Signal<Vec<LogEntry>>,
    mut is_connected: Signal<bool>,
    mut chip_name: Signal<String>,
    mut monitor_active: Signal<bool>,
    mut progress: Signal<u8>,
    mut firmware_name: Signal<String>,
    mut firmware_size: Signal<usize>,
) {
    while let Ok(msg) = eval.recv::<String>().await {
        let Ok(parsed) = serde_json::from_str::<JsMessage>(&msg) else { continue };
        match parsed.r#type.as_str() {
            "log" => {
                let level = match parsed.level.as_str() {
                    "ok" => LogLevel::Ok,
                    "warn" => LogLevel::Warn,
                    "err" => LogLevel::Err,
                    "dim" => LogLevel::Dim,
                    _ => LogLevel::Default,
                };
                log_entries.write().push(LogEntry { msg: parsed.msg, level });
            }
            "connected" => {
                is_connected.set(true);
                chip_name.set(parsed.chip);
            }
            "progress" => progress.set(parsed.percent),
            "firmware_loaded" => {
                firmware_name.set(parsed.name);
                firmware_size.set(parsed.size);
            }
            "monitor_started" => monitor_active.set(true),
            "monitor_stopped" => monitor_active.set(false),
            _ => {}
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Components
// ─────────────────────────────────────────────────────────────────────────────

#[component]
fn ToggleGroup(
    label: String,
    options: Vec<(String, String)>,
    selected: Signal<String>,
) -> Element {
    rsx! {
        div {
            label { class: "text-muted-foreground block mb-1.5 text-xs", "{label}" }
            div { class: "flex rounded-lg overflow-hidden border border-border",
                for (value, display) in options {
                    {
                        let val = value.clone();
                        let val2 = value.clone();
                        rsx! {
                            button {
                                class: if *selected.read() == val {
                                    "flex-1 px-1 py-1.5 text-xs transition-colors bg-primary text-primary-foreground"
                                } else {
                                    "flex-1 px-1 py-1.5 text-xs transition-colors bg-background text-foreground/70 hover:bg-muted/30"
                                },
                                onclick: move |_| selected.set(val2.clone()),
                                "{display}"
                            }
                        }
                    }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main Component
// ─────────────────────────────────────────────────────────────────────────────

#[component]
pub fn FlashPanel() -> Element {
    let toasts = use_toast();

    let mut is_connected = use_signal(|| false);
    let mut chip_name = use_signal(String::new);
    let mut monitor_active = use_signal(|| false);
    let mut log_entries = use_signal(Vec::<LogEntry>::new);
    let mut progress = use_signal(|| 0u8);
    let mut firmware_name = use_signal(String::new);
    let mut firmware_size = use_signal(|| 0usize);
    let mut flashing = use_signal(|| false);
    let mut connecting = use_signal(|| false);

    let mut baud = use_signal(|| "921600".to_string());
    let mut mode = use_signal(|| "keep".to_string());
    let mut freq = use_signal(|| "keep".to_string());
    let mut size = use_signal(|| "keep".to_string());
    let mut address = use_signal(|| "0x10000".to_string());
    let mut compress = use_signal(|| true);
    let mut erase_first = use_signal(|| false);
    let mut wifi_ssid = use_signal(String::new);
    let mut wifi_pass = use_signal(String::new);
    let mut bundled_selection = use_signal(String::new);

    // Load from localStorage on mount
    use_effect(move || {
        document::eval(r#"
            try {
                const c = JSON.parse(localStorage.getItem('flash_options') || '{}');
                return JSON.stringify(c);
            } catch(e) { return '{}'; }
        "#);
    });

    // Sync config to JS window globals whenever they change
    use_effect(move || {
        sync_config_to_js(
            &baud.read(), &mode.read(), &freq.read(), &size.read(), &address.read(),
            *compress.read(), *erase_first.read(), &wifi_ssid.read(), &wifi_pass.read(),
        );
    });

    // Save to localStorage whenever config changes
    use_effect(move || {
        let baud = baud.read().clone();
        let mode = mode.read().clone();
        let freq = freq.read().clone();
        let size = size.read().clone();
        let addr = address.read().clone();
        let compress = *compress.read();
        let erase = *erase_first.read();
        document::eval(&format!(
            r#"localStorage.setItem('flash_options',JSON.stringify({{baud:'{}',mode:'{}',freq:'{}',size:'{}',addr:'{}',compress:{},eraseAll:{}}}));"#,
            baud, mode, freq, size, addr, compress, erase
        ));
    });

    let has_firmware = firmware_size.read().clone() > 0;
    let progress_val = *progress.read();

    rsx! {
        section { class: "panel-shell-strong p-4",

            // ── Title ──
            div { class: "flex items-center gap-2 flex-wrap mb-3",
                h2 { class: "text-xl font-semibold", "Firmware Update" }
                if *is_connected.read() {
                    span { class: "text-xs font-mono text-muted-foreground", "{chip_name}" }
                }
            }

            // ── Connected controls ──
            if *is_connected.read() {
                // ── Wide Disconnect button ──
                button {
                    class: "w-full py-2 rounded-lg border border-destructive/50 text-destructive text-sm font-semibold hover:bg-destructive/10 transition-colors flex items-center justify-center gap-1.5 mb-3",
                    onclick: move |_| {
                        let mut eval = document::eval(JS_DISCONNECT);
                        spawn(async move {
                            process_js_messages(&mut eval, log_entries, is_connected, chip_name, monitor_active, progress, firmware_name, firmware_size).await;
                            is_connected.set(false);
                            monitor_active.set(false);
                            firmware_name.set(String::new());
                            firmware_size.set(0);
                            bundled_selection.set(String::new());
                        });
                    },
                    lucide_dioxus::Plug { class: "w-3.5 h-3.5" }
                    "Disconnect"
                }

                // ── Configuration ──
                div { class: "border border-border rounded-lg p-4 mb-3",
                    p { class: "text-xs font-medium text-muted-foreground mb-3 uppercase tracking-wider", "Configuration" }

                    div { class: "grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs mb-3",
                        ToggleGroup { label: "Baud".to_string(), selected: baud,
                            options: vec![("115200".into(),"115k".into()),("230400".into(),"230k".into()),("460800".into(),"460k".into()),("921600".into(),"921k".into())]
                        }
                        ToggleGroup { label: "Mode".to_string(), selected: mode,
                            options: vec![("keep".into(),"keep".into()),("qio".into(),"QIO".into()),("dio".into(),"DIO".into()),("dout".into(),"DOUT".into())]
                        }
                        ToggleGroup { label: "Freq".to_string(), selected: freq,
                            options: vec![("keep".into(),"keep".into()),("80m".into(),"80M".into()),("40m".into(),"40M".into())]
                        }
                        ToggleGroup { label: "Size".to_string(), selected: size,
                            options: vec![("keep".into(),"keep".into()),("detect".into(),"auto".into()),("4MB".into(),"4M".into()),("8MB".into(),"8M".into()),("16MB".into(),"16M".into())]
                        }
                    }

                    div { class: "flex items-center gap-4 flex-wrap text-xs",
                        div {
                            label { class: "text-muted-foreground block mb-1", "Address" }
                            input {
                                class: "bg-background border border-border rounded px-2 py-1 text-foreground font-mono w-24",
                                r#type: "text",
                                value: "{address}",
                                oninput: move |e| address.set(e.value()),
                            }
                        }
                        div { class: "flex items-center gap-2 pt-4",
                            Switch { checked: compress, on_checked_change: move |val: bool| compress.set(val) }
                            span { class: "text-muted-foreground", "Compress" }
                        }
                        div { class: "flex items-center gap-2 pt-4",
                            Switch { checked: erase_first, on_checked_change: move |val: bool| erase_first.set(val) }
                            span { class: "text-destructive", "Erase first" }
                        }
                    }
                }

                // ── Firmware ──
                // Trigger firmware fetch when selection changes
                {
                    use_effect(move || {
                        let sel = bundled_selection.read().clone();
                        if sel.is_empty() { return; }
                        document::eval(&format!("window.__flashBundledSelection='{}';", sel));
                        let mut eval = document::eval(JS_FETCH_FIRMWARE);
                        spawn(async move {
                            process_js_messages(&mut eval, log_entries, is_connected, chip_name, monitor_active, progress, firmware_name, firmware_size).await;
                        });
                    });
                    rsx! {}
                }

                div {
                    class: "border-2 border-dashed border-border rounded-lg p-6 text-center cursor-pointer hover:border-primary transition-colors mb-3",
                    lucide_dioxus::Upload { class: "w-6 h-6 text-muted-foreground mx-auto mb-1" }
                    p { class: "text-xs text-muted-foreground",
                        if has_firmware {
                            "Latest firmware selected ({firmware_name}, {firmware_size} bytes)"
                        } else {
                            "Loading firmware..."
                        }
                    }
                    p { class: "text-[10px] text-muted-foreground/50 mt-1", "or drop a custom .bin to replace" }
                }

                // ── WiFi Credentials ──
                div { class: "border border-border rounded-lg p-4 mb-3",
                    p { class: "text-xs text-muted-foreground mb-2", "Embed WiFi credentials (optional)" }
                    div { class: "grid grid-cols-2 gap-2 text-xs",
                        div {
                            label { class: "text-muted-foreground block mb-1", "SSID" }
                            input {
                                class: "w-full bg-background border border-border rounded px-2 py-1 text-foreground",
                                r#type: "text",
                                placeholder: "Leave blank for AP provisioning",
                                value: "{wifi_ssid}",
                                oninput: move |e| wifi_ssid.set(e.value()),
                            }
                        }
                        div {
                            label { class: "text-muted-foreground block mb-1", "Password" }
                            input {
                                class: "w-full bg-background border border-border rounded px-2 py-1 text-foreground",
                                r#type: "password",
                                placeholder: "WiFi password",
                                value: "{wifi_pass}",
                                oninput: move |e| wifi_pass.set(e.value()),
                            }
                        }
                    }
                }

                // ── Action row: Flash + Monitor + Reset + Erase ──
                div { class: "flex gap-2 mb-3",
                    button {
                        class: "flex-1 py-2.5 rounded-lg border border-border text-sm font-semibold hover:bg-muted/50 transition-colors flex items-center justify-center gap-2 disabled:opacity-40 disabled:cursor-not-allowed",
                        disabled: !has_firmware || *flashing.read(),
                        onclick: move |_| {
                            flashing.set(true);
                            progress.set(0);
                            spawn(async move {
                                let mut eval = document::eval(JS_FLASH);
                                process_js_messages(&mut eval, log_entries, is_connected, chip_name, monitor_active, progress, firmware_name, firmware_size).await;
                                flashing.set(false);
                                let mut eval2 = document::eval(JS_MONITOR_START);
                                process_js_messages(&mut eval2, log_entries, is_connected, chip_name, monitor_active, progress, firmware_name, firmware_size).await;
                            });
                        },
                        lucide_dioxus::Zap { class: "w-4 h-4" }
                        if *flashing.read() { "Flashing..." } else { "Flash Firmware" }
                    }
                    button {
                        class: "flex-1 py-2.5 rounded-lg border border-yellow-500/50 text-yellow-400 text-sm hover:bg-yellow-500/10 transition-colors flex items-center justify-center gap-1.5",
                        onclick: move |_| {
                            if *monitor_active.read() {
                                document::eval(JS_MONITOR_STOP);
                            } else {
                                let mut eval = document::eval(JS_MONITOR_START);
                                spawn(async move {
                                    process_js_messages(&mut eval, log_entries, is_connected, chip_name, monitor_active, progress, firmware_name, firmware_size).await;
                                });
                            }
                        },
                        lucide_dioxus::Terminal { class: "w-3.5 h-3.5" }
                        if *monitor_active.read() { "Stop" } else { "Monitor" }
                    }
                    button {
                        class: "flex-1 py-2.5 rounded-lg border border-border text-sm hover:bg-muted/50 transition-colors flex items-center justify-center gap-1.5",
                        onclick: move |_| {
                            let mut eval = document::eval(JS_RESET);
                            spawn(async move {
                                process_js_messages(&mut eval, log_entries, is_connected, chip_name, monitor_active, progress, firmware_name, firmware_size).await;
                            });
                        },
                        lucide_dioxus::RotateCcw { class: "w-3.5 h-3.5" }
                        "Reset"
                    }
                    button {
                        class: "flex-1 py-2.5 rounded-lg border border-destructive/50 text-destructive text-sm hover:bg-destructive/10 transition-colors flex items-center justify-center gap-1.5",
                        onclick: move |_| {
                            let mut eval = document::eval(JS_ERASE);
                            spawn(async move {
                                process_js_messages(&mut eval, log_entries, is_connected, chip_name, monitor_active, progress, firmware_name, firmware_size).await;
                                let mut eval2 = document::eval(JS_MONITOR_START);
                                process_js_messages(&mut eval2, log_entries, is_connected, chip_name, monitor_active, progress, firmware_name, firmware_size).await;
                            });
                        },
                        lucide_dioxus::Trash2 { class: "w-3.5 h-3.5" }
                        "Erase All"
                    }
                }

                // ── Progress ──
                if progress_val > 0 && progress_val < 100 {
                    div { class: "mb-2",
                        div { class: "w-full h-4 bg-muted rounded-lg overflow-hidden",
                            div {
                                class: "h-full bg-primary text-[10px] text-primary-foreground flex items-center justify-center transition-all duration-300",
                                style: "width: {progress_val}%",
                                "{progress_val}%"
                            }
                        }
                    }
                }
            }

            // ── Connect button (shown when disconnected) ──
            if !*is_connected.read() {
                button {
                    class: "w-full py-2.5 rounded-lg border border-border text-sm font-semibold hover:bg-muted/50 transition-colors flex items-center justify-center gap-2 disabled:opacity-40 disabled:cursor-not-allowed",
                    disabled: *connecting.read(),
                    onclick: move |_| {
                        connecting.set(true);
                        spawn(async move {
                            // Init terminal first
                            document::eval(JS_INIT_TERMINAL);

                            let mut eval = document::eval(JS_CONNECT);
                            process_js_messages(&mut eval, log_entries, is_connected, chip_name, monitor_active, progress, firmware_name, firmware_size).await;
                            connecting.set(false);

                            if *is_connected.read() {
                                // Auto-fetch latest firmware
                                bundled_selection.set("all".to_string());
                                // Auto-start monitor
                                let mut eval2 = document::eval(JS_MONITOR_START);
                                process_js_messages(&mut eval2, log_entries, is_connected, chip_name, monitor_active, progress, firmware_name, firmware_size).await;
                            }
                        });
                    },
                    lucide_dioxus::Plug { class: "w-4 h-4" }
                    if *connecting.read() { "Connecting..." } else { "Connect" }
                }
            }

            // ── Log ──
            if !log_entries.read().is_empty() {
                div { class: "h-[120px] bg-[#0a0a0c] border border-border rounded-lg p-2 overflow-auto text-xs font-mono leading-relaxed mt-3",
                    for entry in log_entries.read().iter() {
                        div { class: "{entry.level.color_class()}", "{entry.msg}" }
                    }
                }
            }

            // ── Monitor Terminal ──
            div {
                id: "flash-monitor-term",
                class: if *monitor_active.read() { "h-[250px] bg-[#0a0a0c] border border-border rounded-lg overflow-hidden mt-3" } else { "hidden" },
            }
        }
    }
}
