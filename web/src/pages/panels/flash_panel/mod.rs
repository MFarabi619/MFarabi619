mod bridge;
mod components;
mod hooks;
mod state;

use dioxus::prelude::*;
use components::*;
use hooks::use_flash_controller;
use ui::components::button::{Button, ButtonVariant};

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
                Button {
                    class: "w-full py-2 border-destructive/50 text-destructive font-semibold hover:bg-destructive/10 mb-3".to_string(),
                    variant: ButtonVariant::Destructive,
                    on_click: move |_| ctrl.disconnect(),
                    icon_left: rsx! { lucide_dioxus::Plug { class: "w-3.5 h-3.5" } },
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
                Button {
                    class: "gold-button-outline text-sm w-full justify-center py-3".to_string(),
                    variant: ButtonVariant::Outline,
                    disabled: *device.connecting.read(),
                    loading: *device.connecting.read(),
                    on_click: move |_| ctrl.connect(),
                    icon_left: if !*device.connecting.read() {
                        Some(rsx! { lucide_dioxus::Plug { class: "w-4 h-4" } })
                    } else {
                        None
                    },
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
