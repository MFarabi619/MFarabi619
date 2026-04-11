use dioxus::prelude::*;
use dioxus::document::Eval;
use serde::Deserialize;

use super::state::{FlashChipInfo, FlashDeviceState, FlashFirmwareState};

#[derive(Deserialize, Debug)]
pub(crate) struct JsMessage {
    pub r#type: String,
    #[serde(default)]
    pub chip: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub features: Vec<String>,
    #[serde(default)]
    pub mac: String,
    #[serde(default)]
    pub flash_sizes: Vec<String>,
    #[serde(default)]
    pub flash_freqs: Vec<String>,
    #[serde(default)]
    pub bootloader_offset: u32,
    #[serde(default)]
    pub msg: String,
    #[serde(default)]
    pub level: String,
    #[serde(default)]
    pub percent: u8,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub size: usize,
}

// ─────────────────────────────────────────────────────────────────────────────
//  Terminal helpers
// ─────────────────────────────────────────────────────────────────────────────

pub(crate) fn write_to_terminal(msg: &str, ansi_color: &str) {
    let escaped = msg
        .replace('\\', "\\\\")
        .replace('\'', "\\'")
        .replace('\n', "\\n");
    document::eval(&format!(
        "if(window.__flash && window.__flash.term) window.__flash.term.writeln('{}{}\\x1b[0m');",
        ansi_color, escaped
    ));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Message pump
// ─────────────────────────────────────────────────────────────────────────────

pub(crate) async fn process_js_messages(
    eval: &mut Eval,
    mut device: FlashDeviceState,
    mut chip: FlashChipInfo,
    mut firmware: FlashFirmwareState,
) {
    while let Ok(msg) = eval.recv::<String>().await {
        let Ok(parsed) = serde_json::from_str::<JsMessage>(&msg) else {
            continue;
        };
        match parsed.r#type.as_str() {
            "log" => {
                let ansi_color = match parsed.level.as_str() {
                    "ok" => "\\x1b[32m",
                    "warn" => "\\x1b[33m",
                    "err" => "\\x1b[31m",
                    "dim" => "\\x1b[90m",
                    _ => "\\x1b[33m",
                };
                write_to_terminal(&parsed.msg, ansi_color);
            }
            "connected" => {
                device.is_connected.set(true);
                chip.chip_name.set(parsed.chip);
                chip.chip_description.set(parsed.description);
                chip.chip_features.set(parsed.features);
                chip.chip_mac.set(parsed.mac);
                chip.chip_flash_sizes.set(parsed.flash_sizes);
                chip.chip_flash_freqs.set(parsed.flash_freqs);
                chip.bootloader_offset.set(parsed.bootloader_offset);
            }
            "progress" => firmware.progress.set(parsed.percent),
            "firmware_loaded" => {
                firmware.firmware_name.set(parsed.name);
                firmware.firmware_size.set(parsed.size);
            }
            "monitor_started" => device.monitor_active.set(true),
            "monitor_stopped" => device.monitor_active.set(false),
            "device_lost" => {
                device.device_lost.set(true);
                device.is_connected.set(false);
                device.monitor_active.set(false);
            }
            _ => {}
        }
    }
}

pub(crate) async fn eval_and_process(
    js: &str,
    device: FlashDeviceState,
    chip: FlashChipInfo,
    firmware: FlashFirmwareState,
) {
    let mut eval = document::eval(js);
    process_js_messages(&mut eval, device, chip, firmware).await;
}

pub(crate) async fn eval_send_and_process<T: serde::Serialize>(
    js: &str,
    data: T,
    device: FlashDeviceState,
    chip: FlashChipInfo,
    firmware: FlashFirmwareState,
) {
    let mut eval = document::eval(js);
    eval.send(data).ok();
    process_js_messages(&mut eval, device, chip, firmware).await;
}

// ─────────────────────────────────────────────────────────────────────────────
//  JS constants
// ─────────────────────────────────────────────────────────────────────────────

pub(crate) const JS_INIT_TERMINAL: &str = r#"
(function() {
    if (typeof Terminal === 'undefined') return;
    const el = document.getElementById('flash-monitor-term');
    if (!el || el.dataset.initialized) return;
    el.dataset.initialized = 'true';

    if (!window.__flash) {
        window.__flash = {
            port: null,
            ESPLoader: null,
            Transport: null,
            term: null,
            fit: null,
            portInfo: null,
            monitor: { transport: null, stop: false, termHandler: null },
            firmware: { data: null, multiFiles: null },
        };
    }

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

    window.__flash.term = term;
    window.__flash.fit = fit;

    window.__stopMonitor = async function() {
        const f = window.__flash;
        f.monitor.stop = true;
        if (f.monitor.termHandler) {
            f.monitor.termHandler.dispose();
            f.monitor.termHandler = null;
        }
        if (f.monitor.transport) {
            try {
                await f.monitor.transport.disconnect();
                await f.monitor.transport.waitForUnlock(1500);
            } catch(e) {}
            f.monitor.transport = null;
        }
        if (f.port) {
            try {
                if (f.port.readable || f.port.writable) await f.port.close();
            } catch(e) {}
        }
    };
})();
"#;

pub(crate) const JS_CONNECT: &str = r#"
(async function() {
    if (!navigator.serial) {
        dioxus.send(JSON.stringify({type:'log', msg:'Web Serial not supported. Use Chrome/Edge.', level:'err'}));
        return 'error';
    }
    try {
        const port = await navigator.serial.requestPort();
        const f = window.__flash;
        f.port = port;
        f.portInfo = port.getInfo();

        dioxus.send(JSON.stringify({type:'log', msg:'Loading esptool...', level:'dim'}));
        const { ESPLoader, Transport } = await import('https://unpkg.com/esptool-js/bundle.js');
        f.ESPLoader = ESPLoader;
        f.Transport = Transport;

        const baud = parseInt(await dioxus.recv()) || 921600;
        const transport = new Transport(port, true);

        const espTerminal = {
            clean() { if (f.term) f.term.clear(); },
            writeLine(d) { if (f.term) f.term.writeln('\x1b[90m' + d + '\x1b[0m'); },
            write(d) { if (f.term) f.term.write('\x1b[90m' + d + '\x1b[0m'); }
        };

        const loader = new ESPLoader({
            transport, baudrate: baud, romBaudrate: 115200,
            terminal: espTerminal
        });

        dioxus.send(JSON.stringify({type:'log', msg:'Connecting at ' + baud + '...', level:'warn'}));
        const chipDesc = await loader.main();

        const features = await loader.chip.getChipFeatures(loader);
        const mac = await loader.chip.readMac(loader);
        const flashSizes = Object.keys(loader.chip.FLASH_SIZES);
        const flashFreqs = Object.keys(loader.chip.FLASH_FREQUENCY);

        dioxus.send(JSON.stringify({type:'log', msg:'Connected: ' + chipDesc, level:'ok'}));
        dioxus.send(JSON.stringify({
            type: 'connected',
            chip: loader.chip.CHIP_NAME,
            description: chipDesc,
            features: features,
            mac: mac,
            flash_sizes: flashSizes,
            flash_freqs: flashFreqs,
            bootloader_offset: loader.chip.BOOTLOADER_FLASH_OFFSET
        }));

        await transport.disconnect();

        try {
            if (!port.readable) await port.open({ baudRate: 115200 });
            const rst = new f.Transport(port, true);
            await rst.setDTR(false);
            await rst.setRTS(true);
            await new Promise(r => setTimeout(r, 100));
            await rst.setRTS(false);
            await rst.disconnect();
        } catch(e) {}

        return 'ok';
    } catch(err) {
        dioxus.send(JSON.stringify({type:'log', msg:'Connect failed: ' + err.message, level:'err'}));
        const f = window.__flash;
        f.port = null;
        return 'error';
    }
})()
"#;

pub(crate) const JS_MONITOR_START: &str = r#"
(async function() {
    const f = window.__flash;
    if (!f || !f.port) {
        dioxus.send(JSON.stringify({type:'log', msg:'No port available', level:'err'}));
        return;
    }

    f.monitor.stop = false;
    const baud = parseInt(await dioxus.recv()) || 115200;

    try {
        if (!f.port.readable) {
            await f.port.open({ baudRate: baud });
        }

        const transport = new f.Transport(f.port, true);
        f.monitor.transport = transport;

        transport.setDeviceLostCallback(() => {
            dioxus.send(JSON.stringify({type:'device_lost'}));
        });

        dioxus.send(JSON.stringify({type:'log', msg:'Monitor started at ' + baud + ' baud', level:'ok'}));
        dioxus.send(JSON.stringify({type:'monitor_started'}));

        if (f.term) {
            f.monitor.termHandler = f.term.onData(function(data) {
                const writer = f.port.writable.getWriter();
                writer.write(new TextEncoder().encode(data));
                writer.releaseLock();
            });
        }

        await transport.rawRead(
            function(value) { if (f.term) f.term.write(value); },
            function() { return f.monitor.stop === true; }
        );
    } catch(err) {
        if (!f.monitor.stop) {
            dioxus.send(JSON.stringify({type:'log', msg:'Monitor error: ' + err.message, level:'err'}));
        }
    }

    try {
        if (f.monitor.termHandler) { f.monitor.termHandler.dispose(); f.monitor.termHandler = null; }
        if (f.monitor.transport) { await f.monitor.transport.disconnect(); f.monitor.transport = null; }
    } catch(e) {}

    dioxus.send(JSON.stringify({type:'monitor_stopped'}));
})()
"#;

pub(crate) const JS_MONITOR_STOP: &str = r#"
if (window.__flash) window.__flash.monitor.stop = true;
"#;

pub(crate) const JS_FLASH: &str = r#"
(async function() {
    const f = window.__flash;
    if (!f || !f.port) return 'no_port';

    await window.__stopMonitor();

    try {
        const config = await dioxus.recv();
        const baud = parseInt(config.baud) || 921600;

        if (!f.port.readable) {
            await f.port.open({ baudRate: baud });
        }

        const transport = new f.Transport(f.port, true);
        const espTerminal = {
            clean() { if (f.term) f.term.clear(); },
            writeLine(d) { if (f.term) f.term.writeln('\x1b[90m' + d + '\x1b[0m'); },
            write(d) { if (f.term) f.term.write('\x1b[90m' + d + '\x1b[0m'); }
        };

        const loader = new f.ESPLoader({
            transport, baudrate: baud, romBaudrate: 115200,
            terminal: espTerminal
        });

        dioxus.send(JSON.stringify({type:'log', msg:'Reconnecting for flash...', level:'warn'}));
        await loader.main();

        const flashMode = config.mode || 'keep';
        const flashFreq = config.freq || 'keep';
        const flashSize = config.size || 'detect';
        const compress = config.compress !== false;
        const eraseAll = config.eraseAll === true;
        const ssid = (config.wifiSsid || '').trim();
        const pass = config.wifiPass || '';

        let fileArray;
        const fw = f.firmware.data;
        const multi = f.firmware.multiFiles;

        if (multi) {
            fileArray = multi.map(file => ({ data: new Uint8Array(file.data), address: file.address }));
            if (ssid) {
                patchSentinel(fileArray[2].data, '@@WIFI_SSID@@', ssid, 33);
                patchSentinel(fileArray[2].data, '@@WIFI_PASS@@', pass, 65);
                dioxus.send(JSON.stringify({type:'log', msg:'Embedded WiFi: ' + ssid, level:'ok'}));
            }
            dioxus.send(JSON.stringify({type:'log', msg:'Flashing 3 files (bootloader + partitions + app)...', level:'warn'}));
        } else {
            const addr = parseInt(config.addr || '0x10000', 16) || 0x10000;
            const dataToFlash = new Uint8Array(fw);
            if (ssid) {
                patchSentinel(dataToFlash, '@@WIFI_SSID@@', ssid, 33);
                patchSentinel(dataToFlash, '@@WIFI_PASS@@', pass, 65);
                dioxus.send(JSON.stringify({type:'log', msg:'Embedded WiFi: ' + ssid, level:'ok'}));
            }
            fileArray = [{ data: dataToFlash, address: addr }];
            dioxus.send(JSON.stringify({type:'log', msg:'Flashing to 0x' + addr.toString(16) + '...', level:'warn'}));
        }

        const totalAllFiles = fileArray.reduce((sum, file) => sum + file.data.length, 0);
        let cumulativeWritten = 0;
        let lastFileIndex = 0;
        const fileSizes = fileArray.map(file => file.data.length);

        await loader.writeFlash({
            fileArray,
            flashSize: flashSize,
            flashMode: flashMode,
            flashFreq: flashFreq,
            eraseAll,
            compress,
            reportProgress(fileIndex, written, total) {
                while (lastFileIndex < fileIndex) {
                    cumulativeWritten += fileSizes[lastFileIndex];
                    lastFileIndex++;
                }
                const overall = Math.round(((cumulativeWritten + written) / totalAllFiles) * 100);
                dioxus.send(JSON.stringify({type:'progress', percent: Math.min(overall, 99)}));
            },
            calculateMD5Hash(image) {
                if (typeof SparkMD5 !== 'undefined') {
                    return SparkMD5.ArrayBuffer.hash(image.buffer);
                }
                return null;
            }
        });

        dioxus.send(JSON.stringify({type:'progress', percent: 100}));
        dioxus.send(JSON.stringify({type:'log', msg:'Flash complete!', level:'ok'}));

        try { await loader.after('hard_reset'); } catch(e) {
            try {
                await transport.setDTR(false);
                await transport.setRTS(true);
                await new Promise(r => setTimeout(r, 100));
                await transport.setRTS(false);
            } catch(e2) {}
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

pub(crate) const JS_FETCH_FIRMWARE: &str = r#"
(async function() {
    const val = await dioxus.recv();
    if (!val) return;
    const f = window.__flash;

    if (val === 'all') {
        try {
            dioxus.send(JSON.stringify({type:'log', msg:'Fetching all firmware files...', level:'warn'}));
            const [bl, pt, fw] = await Promise.all([
                fetch('/assets/bootloader.bin').then(r => r.arrayBuffer()),
                fetch('/assets/partitions.bin').then(r => r.arrayBuffer()),
                fetch('/assets/firmware.bin').then(r => r.arrayBuffer())
            ]);
            f.firmware.multiFiles = [
                { data: new Uint8Array(bl), address: 0x0 },
                { data: new Uint8Array(pt), address: 0x8000 },
                { data: new Uint8Array(fw), address: 0x10000 }
            ];
            f.firmware.data = f.firmware.multiFiles[2].data;
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
        f.firmware.data = new Uint8Array(buf);
        f.firmware.multiFiles = null;
        const name = val.split('/').pop();
        dioxus.send(JSON.stringify({type:'firmware_loaded', name: name, size: buf.byteLength}));
        dioxus.send(JSON.stringify({type:'log', msg:'Loaded: ' + name + ' (' + (buf.byteLength/1024).toFixed(1) + ' KB)', level:'ok'}));
    } catch(err) {
        dioxus.send(JSON.stringify({type:'log', msg:'Failed to fetch: ' + err.message, level:'err'}));
    }
})()
"#;

pub(crate) const JS_DISCONNECT: &str = r#"
(async function() {
    const f = window.__flash;
    await window.__stopMonitor();
    try { if (f.port && f.port.readable) await f.port.close(); } catch(e) {}
    f.port = null;
    f.portInfo = null;
    f.firmware.data = null;
    f.firmware.multiFiles = null;
    dioxus.send(JSON.stringify({type:'log', msg:'Disconnected', level:'dim'}));
})()
"#;

pub(crate) const JS_ERASE: &str = r#"
(async function() {
    const f = window.__flash;
    if (!f || !f.port) return;

    await window.__stopMonitor();

    try {
        const baud = parseInt(await dioxus.recv()) || 921600;
        if (!f.port.readable) await f.port.open({ baudRate: baud });

        const transport = new f.Transport(f.port, true);
        const loader = new f.ESPLoader({
            transport, baudrate: baud, romBaudrate: 115200,
            terminal: {
                clean() {},
                writeLine(d) { if (f.term) f.term.writeln('\x1b[90m' + d + '\x1b[0m'); },
                write(d) { if (f.term) f.term.write('\x1b[90m' + d + '\x1b[0m'); }
            }
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

pub(crate) const JS_RESET: &str = r#"
(async function() {
    const f = window.__flash;
    if (!f || !f.port) return;

    await window.__stopMonitor();

    try {
        const baud = parseInt(await dioxus.recv()) || 921600;
        if (!f.port.readable) await f.port.open({ baudRate: baud });
        const transport = new f.Transport(f.port, true);
        await transport.setDTR(false);
        await transport.setRTS(true);
        await new Promise(r => setTimeout(r, 100));
        await transport.setRTS(false);
        dioxus.send(JSON.stringify({type:'log', msg:'Hard reset.', level:'ok'}));
        await transport.disconnect();
    } catch(err) {
        dioxus.send(JSON.stringify({type:'log', msg:'Reset error: ' + err.message, level:'err'}));
    }
    return 'done';
})()
"#;

pub(crate) const JS_CLEANUP: &str = r#"
if (window.__stopMonitor) window.__stopMonitor();
try {
    const f = window.__flash;
    if (f && f.port && f.port.readable) f.port.close();
} catch(e) {}
window.__flash = null;
"#;
