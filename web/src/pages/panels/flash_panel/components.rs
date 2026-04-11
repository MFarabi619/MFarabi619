use dioxus::prelude::*;
use ui::components::switch::Switch;

use super::hooks::FlashController;
use super::state::*;

// ─────────────────────────────────────────────────────────────────────────────
//  ToggleGroup
// ─────────────────────────────────────────────────────────────────────────────

#[component]
pub fn ToggleGroup(
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
                        let key = value.clone();
                        let val = value.clone();
                        let val2 = value.clone();
                        rsx! {
                            button {
                                key: "{key}",
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
//  ConfigSection
// ─────────────────────────────────────────────────────────────────────────────

#[component]
pub fn ConfigSection(config: FlashConfig, chip: FlashChipInfo) -> Element {
    let size_options = {
        let chip_sizes = chip.chip_flash_sizes.read();
        let mut opts = vec![
            ("keep".to_string(), "keep".to_string()),
            ("detect".to_string(), "auto".to_string()),
        ];
        if chip_sizes.is_empty() {
            opts.extend([
                ("4MB".to_string(), "4".to_string()),
                ("8MB".to_string(), "8".to_string()),
                ("16MB".to_string(), "16".to_string()),
            ]);
        } else {
            for s in chip_sizes.iter() {
                let display = s.replace("MB", "").replace("KB", "");
                opts.push((s.clone(), display));
            }
        }
        opts
    };

    let freq_options = {
        let chip_freqs = chip.chip_flash_freqs.read();
        let mut opts = vec![("keep".to_string(), "keep".to_string())];
        if chip_freqs.is_empty() {
            opts.extend([
                ("80m".to_string(), "80".to_string()),
                ("40m".to_string(), "40".to_string()),
            ]);
        } else {
            for f in chip_freqs.iter() {
                let display = f.replace("m", "");
                opts.push((f.clone(), display));
            }
        }
        opts
    };

    rsx! {
        div { class: "border border-border rounded-lg p-4",
            p { class: "text-xs font-medium text-muted-foreground mb-3 uppercase tracking-wider", "Configuration" }

            div { class: "grid grid-cols-2 gap-3 text-xs mb-3",
                ToggleGroup { label: "Baud (bps)".to_string(), selected: config.baud,
                    options: vec![("115200".into(),"115k".into()),("230400".into(),"230k".into()),("460800".into(),"460k".into()),("921600".into(),"921k".into())]
                }
                ToggleGroup { label: "Flash Mode".to_string(), selected: config.mode,
                    options: vec![("keep".into(),"keep".into()),("qio".into(),"QIO".into()),("dio".into(),"DIO".into()),("dout".into(),"DOUT".into())]
                }
                ToggleGroup { label: "Frequency (MHz)".to_string(), selected: config.freq,
                    options: freq_options
                }
                ToggleGroup { label: "Size (MB)".to_string(), selected: config.size,
                    options: size_options
                }
            }

            div { class: "flex items-center gap-4 flex-wrap text-xs",
                div {
                    label { class: "text-muted-foreground block mb-1", "Address" }
                    input {
                        class: "bg-background border border-border rounded px-2 py-1 text-foreground font-mono w-24",
                        r#type: "text",
                        value: "{config.address}",
                        oninput: move |e| config.address.set(e.value()),
                    }
                }
                div { class: "flex items-center gap-2 pt-4",
                    Switch { checked: config.compress, on_checked_change: move |val: bool| config.compress.set(val) }
                    span { class: "text-muted-foreground", "Compress" }
                }
                div { class: "flex items-center gap-2 pt-4",
                    Switch { checked: config.erase_first, on_checked_change: move |val: bool| config.erase_first.set(val) }
                    span { class: "text-destructive", "Erase first" }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  WiFiSection
// ─────────────────────────────────────────────────────────────────────────────

#[component]
pub fn WiFiSection(config: FlashConfig) -> Element {
    rsx! {
        div { class: "border border-border rounded-lg p-4",
            p { class: "text-xs font-medium text-muted-foreground mb-3 uppercase tracking-wider", "WiFi Credentials" }
            div { class: "flex flex-col gap-2 text-xs",
                div {
                    label { class: "text-muted-foreground block mb-1", "SSID" }
                    input {
                        class: "w-full bg-background border border-border rounded px-2 py-1 text-foreground",
                        r#type: "text",
                        placeholder: "Leave blank for AP provisioning",
                        value: "{config.wifi_ssid}",
                        oninput: move |e| config.wifi_ssid.set(e.value()),
                    }
                }
                div {
                    label { class: "text-muted-foreground block mb-1", "Password" }
                    input {
                        class: "w-full bg-background border border-border rounded px-2 py-1 text-foreground",
                        r#type: "password",
                        placeholder: "WiFi password",
                        value: "{config.wifi_pass}",
                        oninput: move |e| config.wifi_pass.set(e.value()),
                    }
                }
            }
            p { class: "text-[10px] text-muted-foreground/50 mt-2", "Patched into firmware binary at flash time via sentinel slots" }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  FirmwareSection
// ─────────────────────────────────────────────────────────────────────────────

#[component]
pub fn FirmwareSection(
    firmware: FlashFirmwareState,
    config: FlashConfig,
    chip: FlashChipInfo,
) -> Element {
    let has_firmware = *firmware.firmware_size.read() > 0;

    rsx! {
        div { class: "border-2 border-dashed border-border rounded-lg p-6 flex flex-col items-center justify-center hover:border-primary transition-colors cursor-pointer",
            lucide_dioxus::Upload { class: "w-8 h-8 text-muted-foreground mb-2" }
            if has_firmware {
                p { class: "text-sm font-medium text-foreground mb-1", "{firmware.firmware_name}" }
                p { class: "text-xs text-muted-foreground mb-3",
                    "{*firmware.firmware_size.read() / 1024} KB"
                }
                div { class: "text-[10px] text-muted-foreground/70 space-y-0.5 text-center",
                    if !chip.chip_name.read().is_empty() {
                        p { "Target: {chip.chip_name}" }
                    }
                    p { "Address: {config.address}" }
                    p { "Mode: {config.mode} · Freq: {config.freq} · Size: {config.size}" }
                    if *config.compress.read() {
                        p { "Compression enabled" }
                    }
                }
            } else {
                p { class: "text-sm text-muted-foreground mb-1", "Loading firmware..." }
            }
            p { class: "text-[10px] text-muted-foreground/50 mt-3", "or drop a custom .bin to replace" }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ActionRow
// ─────────────────────────────────────────────────────────────────────────────

#[component]
pub fn ActionRow(controller: FlashController) -> Element {
    let has_firmware = *controller.firmware.firmware_size.read() > 0;
    let flashing = *controller.firmware.flashing.read();
    let monitoring = *controller.device.monitor_active.read();

    rsx! {
        div { class: "flex gap-2 mb-3",
            button {
                class: "flex-1 py-2.5 rounded-lg border border-border text-sm font-semibold hover:bg-muted/50 transition-colors flex items-center justify-center gap-2 disabled:opacity-40 disabled:cursor-not-allowed",
                disabled: !has_firmware || flashing,
                onclick: move |_| controller.flash(),
                lucide_dioxus::Zap { class: "w-4 h-4" }
                if flashing { "Flashing..." } else { "Flash Firmware" }
            }
            button {
                class: "flex-1 py-2.5 rounded-lg border border-yellow-500/50 text-yellow-400 text-sm hover:bg-yellow-500/10 transition-colors flex items-center justify-center gap-1.5",
                onclick: move |_| controller.toggle_monitor(),
                lucide_dioxus::Terminal { class: "w-3.5 h-3.5" }
                if monitoring { "Stop" } else { "Monitor" }
            }
            button {
                class: "flex-1 py-2.5 rounded-lg border border-border text-sm hover:bg-muted/50 transition-colors flex items-center justify-center gap-1.5",
                onclick: move |_| controller.reset(),
                lucide_dioxus::RotateCcw { class: "w-3.5 h-3.5" }
                "Reset"
            }
            button {
                class: "flex-1 py-2.5 rounded-lg border border-destructive/50 text-destructive text-sm hover:bg-destructive/10 transition-colors flex items-center justify-center gap-1.5",
                onclick: move |_| controller.erase(),
                lucide_dioxus::Trash2 { class: "w-3.5 h-3.5" }
                "Erase All"
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ProgressBar
// ─────────────────────────────────────────────────────────────────────────────

#[component]
pub fn ProgressBar(progress: Signal<u8>) -> Element {
    let val = *progress.read();
    if val > 0 && val < 100 {
        rsx! {
            div { class: "mb-2",
                div { class: "w-full h-4 bg-muted rounded-lg overflow-hidden",
                    div {
                        class: "h-full bg-primary text-[10px] text-primary-foreground flex items-center justify-center transition-all duration-300",
                        style: "width: {val}%",
                        "{val}%"
                    }
                }
            }
        }
    } else {
        rsx! {}
    }
}
