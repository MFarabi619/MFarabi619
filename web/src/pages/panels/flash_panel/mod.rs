mod bridge;
mod components;
mod hooks;
mod state;

use dioxus::prelude::*;
use components::*;
use hooks::use_flash_controller;

#[component]
pub fn FlashPanel() -> Element {
    let ctrl = use_flash_controller();
    let device = ctrl.device;
    let chip = ctrl.chip;

    rsx! {
        section { id: "flash-panel", class: "panel-shell-strong p-4",

            // ── Title ──
            div { class: "flex items-center gap-2 flex-wrap mb-3",
                h2 { class: "text-xl font-semibold", "Firmware Update" }
                if *device.is_connected.read() {
                    span { class: "text-xs font-mono text-muted-foreground", "{chip.chip_name}" }
                    if !chip.chip_mac.read().is_empty() {
                        span { class: "text-[10px] font-mono text-muted-foreground/70", "{chip.chip_mac}" }
                    }
                }
            }

            // ── Chip info ──
            if *device.is_connected.read() && !chip.chip_description.read().is_empty() {
                div { class: "text-xs text-muted-foreground mb-2",
                    span { "{chip.chip_description}" }
                    if !chip.chip_features.read().is_empty() {
                        span { class: "ml-2 text-muted-foreground/60",
                            "({chip.chip_features.read().join(\", \")})"
                        }
                    }
                }
            }

            // ── Connected controls ──
            if *device.is_connected.read() {
                button {
                    class: "w-full py-2 rounded-lg border border-destructive/50 text-destructive text-sm font-semibold hover:bg-destructive/10 transition-colors flex items-center justify-center gap-1.5 mb-3",
                    onclick: move |_| ctrl.disconnect(),
                    lucide_dioxus::Plug { class: "w-3.5 h-3.5" }
                    "Disconnect"
                }

                div { class: "grid grid-cols-1 lg:grid-cols-2 gap-3 mb-3",
                    div { class: "flex flex-col gap-3",
                        ConfigSection { config: ctrl.config, chip: ctrl.chip }
                        WiFiSection { config: ctrl.config }
                    }
                    FirmwareSection { firmware: ctrl.firmware, config: ctrl.config, chip: ctrl.chip }
                }

                ActionRow { controller: ctrl }
                ProgressBar { progress: ctrl.firmware.progress }
            }

            // ── Connect button ──
            if !*device.is_connected.read() {
                button {
                    class: "w-full py-2.5 rounded-lg border border-border text-sm font-semibold hover:bg-muted/50 transition-colors flex items-center justify-center gap-2 disabled:opacity-40 disabled:cursor-not-allowed",
                    disabled: *device.connecting.read(),
                    onclick: move |_| ctrl.connect(),
                    lucide_dioxus::Plug { class: "w-4 h-4" }
                    if *device.connecting.read() { "Connecting..." } else { "Connect" }
                }
            }

            // ── Terminal ──
            div {
                id: "flash-monitor-term",
                class: if *device.is_connected.read() { "h-[400px] bg-[#0a0a0c] border border-border rounded-lg overflow-hidden mt-3" } else { "hidden" },
            }
        }
    }
}
