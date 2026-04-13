use dioxus::prelude::*;
use ui::components::button::{Button, ButtonVariant};

#[component]
pub fn BluetoothPanel() -> Element {
    let mut initialized = use_signal(|| false);

    use_effect(move || {
        if *initialized.peek() {
            return;
        }
        initialized.set(true);

        document::eval(
            r#"
            setTimeout(function() {
                const panel = document.getElementById('bluetooth-panel');
                if (!panel || panel.dataset.initialized) return;
                panel.dataset.initialized = 'true';

                const pairBtn = document.getElementById('bt-pair-btn');
                const disconnectBtn = document.getElementById('bt-disconnect-btn');
                const statusEl = document.getElementById('bt-status');
                const termEl = document.getElementById('bt-terminal');

                let device = null;
                let server = null;
                let rxChar = null;
                let txChar = null;
                let term = null;

                const NUS_SERVICE = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
                const NUS_RX      = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
                const NUS_TX      = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

                function setStatus(text) { statusEl.textContent = text; }

                function showConnected() {
                    pairBtn.style.display = 'none';
                    disconnectBtn.style.display = '';
                    termEl.style.display = '';
                }

                function showDisconnected() {
                    pairBtn.style.display = '';
                    disconnectBtn.style.display = 'none';
                }

                function initTerminal() {
                    if (term) return;
                    if (typeof Terminal === 'undefined') return;
                    term = new Terminal({
                        cursorBlink: true, fontSize: 13,
                        fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
                        theme: {
                            background: '#0a0a0c', foreground: '#d4a84b', cursor: '#f5b72b',
                            selectionBackground: 'rgba(245, 183, 43, 0.3)',
                            black: '#0a0a0c', red: '#e06c6c', green: '#6cc070',
                            yellow: '#f5b72b', blue: '#6c9ee0', magenta: '#c06cc0',
                            cyan: '#6cc0c0', white: '#d4a84b'
                        }
                    });
                    if (typeof FitAddon !== 'undefined') {
                        const fit = new FitAddon.FitAddon();
                        term.loadAddon(fit);
                        term.open(termEl);
                        fit.fit();
                        window.addEventListener('resize', () => fit.fit());
                    } else {
                        term.open(termEl);
                    }
                }

                pairBtn.addEventListener('click', async function() {
                    if (!navigator.bluetooth) {
                        setStatus('Web Bluetooth not supported. Use Chrome/Edge on HTTPS.');
                        return;
                    }
                    try {
                        setStatus('Scanning...');
                        device = await navigator.bluetooth.requestDevice({
                            filters: [{ services: [NUS_SERVICE] }],
                            optionalServices: [NUS_SERVICE]
                        });

                        device.addEventListener('gattserverdisconnected', function() {
                            setStatus('Disconnected');
                            showDisconnected();
                            if (term) term.write('\r\n\x1b[31m[BLE disconnected]\x1b[0m\r\n');
                        });

                        setStatus('Connecting to ' + device.name + '...');
                        server = await device.gatt.connect();
                        const service = await server.getPrimaryService(NUS_SERVICE);

                        rxChar = await service.getCharacteristic(NUS_RX);
                        txChar = await service.getCharacteristic(NUS_TX);

                        await txChar.startNotifications();
                        txChar.addEventListener('characteristicvaluechanged', function(event) {
                            const decoder = new TextDecoder();
                            const text = decoder.decode(event.target.value);
                            if (term) term.write(text);
                        });

                        initTerminal();
                        showConnected();
                        setStatus('Connected: ' + (device.name || 'BLE Device'));
                        if (term) term.write('\x1b[32m[BLE connected: ' + device.name + ']\x1b[0m\r\n');

                        term.onData(function(data) {
                            if (rxChar) {
                                const encoder = new TextEncoder();
                                rxChar.writeValueWithoutResponse(encoder.encode(data));
                            }
                        });

                    } catch (err) {
                        setStatus('Error: ' + err.message);
                    }
                });

                disconnectBtn.addEventListener('click', function() {
                    if (device && device.gatt.connected) {
                        device.gatt.disconnect();
                    }
                    showDisconnected();
                    setStatus('Disconnected');
                });

                showDisconnected();
                setStatus('Ready to pair');
            }, 100);
        "#,
        );
    });

    rsx! {
        section { id: "bluetooth-panel", class: "border border-border rounded-lg bg-card p-4",
            div { class: "flex items-center gap-2 mb-3",
                h2 { class: "text-xl font-semibold", "Bluetooth" }
                span { id: "bt-status", class: "text-sm text-muted-foreground", role: "status", aria_live: "polite" }
            }

            div { class: "flex gap-2 mb-3",
                Button { id: "bt-pair-btn", variant: ButtonVariant::Outline,
                    class: "px-3 py-1.5 text-sm hover:bg-muted/50".to_string(),
                    aria_label: "Pair via Bluetooth",
                    lucide_dioxus::Bluetooth { class: "w-4 h-4" }
                    "Pair via Bluetooth"
                }
                Button { id: "bt-disconnect-btn", variant: ButtonVariant::Outline,
                    class: "px-3 py-1.5 text-sm text-muted-foreground hover:bg-muted/50".to_string(), style: "display:none",
                    aria_label: "Disconnect Bluetooth",
                    "Disconnect"
                }
            }

            div { id: "bt-terminal", class: "h-[250px] bg-[#0a0a0c] rounded-lg overflow-hidden", style: "display:none" }
        }
    }
}
