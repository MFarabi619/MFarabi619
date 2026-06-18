use dioxus::prelude::*;
use dioxus_primitives::alert_dialog::{
    AlertDialogAction, AlertDialogActions, AlertDialogCancel, AlertDialogContent,
    AlertDialogDescription, AlertDialogRoot, AlertDialogTitle,
};
use ui::components::button::{Button, ButtonVariant};
use ui::components::input::Input;
use ui::components::label::Label;
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
    let label_slug = label
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() {
                character.to_ascii_lowercase()
            } else {
                '-'
            }
        })
        .collect::<String>();
    let label_element_id = format!("flash-toggle-group-{label_slug}-label");
    let label_element_signal = use_signal({
        let label_element_id = label_element_id.clone();
        move || Some(label_element_id.clone())
    });

    rsx! {
        div {
            Label {
                id: label_element_signal,
                class: Some("text-muted-foreground text-xs".to_string()),
                "{label}"
            }
            div {
                class: "flex rounded-lg overflow-hidden border border-border",
                role: "radiogroup",
                aria_labelledby: label_element_id.clone(),
                for (value, display) in options {
                    {
                        let is_selected = *selected.read() == value;
                        let val = value.clone();
                        rsx! {
                            Button {
                                key: "{value}",
                                variant: ButtonVariant::Ghost,
                                class: {
                                    if is_selected {
                                    "flex-1 px-1 py-1.5 text-xs bg-primary text-primary-foreground rounded-none border-0 hover:bg-primary/90"
                                    } else {
                                    "flex-1 px-1 py-1.5 text-xs bg-background text-foreground/70 rounded-none border-0 hover:bg-muted/30"
                                    }.to_string()
                                },
                                role: "radio",
                                aria_checked: is_selected,
                                aria_pressed: Some(is_selected),
                                on_click: move |_| selected.set(val.clone()),
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
    let address_input_label = use_signal(|| Some("flash-address-input".to_string()));
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
                    Label {
                        for_id: address_input_label,
                        class: Some("text-muted-foreground block mb-1 text-xs".to_string()),
                        "Address"
                    }
                    Input {
                        id: Some("flash-address-input".to_string()),
                        class: Some("bg-background border border-border rounded px-2 py-1 h-auto text-foreground font-mono w-24 focus:ring-0 focus:ring-offset-0".to_string()),
                        input_type: "text".to_string(),
                        aria_label: Some("Flash address".to_string()),
                        value: config.address.read().clone(),
                        on_input: Some(Callback::new(move |e: FormEvent| config.address.set(e.value()))),
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
    let wifi_ssid_input_label = use_signal(|| Some("flash-wifi-ssid-input".to_string()));
    let wifi_password_input_label = use_signal(|| Some("flash-wifi-password-input".to_string()));

    rsx! {
        div { class: "border border-border rounded-lg p-4",
            p { class: "text-xs font-medium text-muted-foreground mb-3 uppercase tracking-wider", "WiFi Credentials" }
            div { class: "flex flex-col gap-2 text-xs",
                div {
                    Label {
                        for_id: wifi_ssid_input_label,
                        class: Some("text-muted-foreground block mb-1 text-xs".to_string()),
                        "SSID"
                    }
                    Input {
                        id: Some("flash-wifi-ssid-input".to_string()),
                        class: Some("w-full bg-background border border-border rounded px-2 py-1 h-auto text-foreground focus:ring-0 focus:ring-offset-0".to_string()),
                        input_type: "text".to_string(),
                        aria_label: Some("WiFi SSID".to_string()),
                        placeholder: "Leave blank for AP provisioning".to_string(),
                        value: config.wifi_ssid.read().clone(),
                        on_input: Some(Callback::new(move |e: FormEvent| config.wifi_ssid.set(e.value()))),
                    }
                }
                div {
                    Label {
                        for_id: wifi_password_input_label,
                        class: Some("text-muted-foreground block mb-1 text-xs".to_string()),
                        "Password"
                    }
                    Input {
                        id: Some("flash-wifi-password-input".to_string()),
                        class: Some("w-full bg-background border border-border rounded px-2 py-1 h-auto text-foreground focus:ring-0 focus:ring-offset-0".to_string()),
                        input_type: "password".to_string(),
                        aria_label: Some("WiFi password".to_string()),
                        placeholder: "WiFi password".to_string(),
                        value: config.wifi_pass.read().clone(),
                        on_input: Some(Callback::new(move |e: FormEvent| config.wifi_pass.set(e.value()))),
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
    controller: FlashController,
    config: FlashConfig,
    chip: FlashChipInfo,
) -> Element {
    let firmware = controller.firmware;
    let has_firmware = *firmware.firmware_size.read() > 0;

    rsx! {
        div {
            class: "border-2 border-dashed border-border rounded-lg p-6 flex flex-col items-center justify-center hover:border-primary transition-colors cursor-pointer",
            onclick: move |_| controller.select_firmware(),
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
                p { class: "text-[10px] text-muted-foreground/50 mt-3", "Click to replace" }
            } else {
                p { class: "text-sm text-muted-foreground mb-1", "Select a firmware .bin file" }
                p { class: "text-[10px] text-muted-foreground/50 mt-1", "Click to browse" }
            }
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
    let mut confirm_erase = use_signal(|| false);

    rsx! {
        div { class: "flex gap-2 mb-3",
            Button {
                class: "flex-1 py-2.5 font-semibold hover:bg-muted/50".to_string(),
                variant: ButtonVariant::Outline,
                disabled: !has_firmware || flashing,
                loading: flashing,
                on_click: move |_| controller.flash(),
                if !flashing {
                    lucide_dioxus::Zap { class: "w-4 h-4" }
                }
                if flashing { "Flashing..." } else { "Flash Firmware" }
            }
            Button {
                class: "flex-1 py-2.5 border-yellow-500/50 text-yellow-400 hover:bg-yellow-500/10".to_string(),
                variant: ButtonVariant::Outline,
                on_click: move |_| controller.toggle_monitor(),
                icon_left: rsx! { lucide_dioxus::Terminal { class: "w-3.5 h-3.5" } },
                if monitoring { "Stop" } else { "Monitor" }
            }
            Button {
                class: "flex-1 py-2.5 hover:bg-muted/50".to_string(),
                variant: ButtonVariant::Outline,
                on_click: move |_| controller.reset(),
                icon_left: rsx! { lucide_dioxus::RotateCcw { class: "w-3.5 h-3.5" } },
                "Reset"
            }
            Button {
                class: "flex-1 py-2.5 border-destructive/50 text-destructive hover:bg-destructive/10".to_string(),
                variant: ButtonVariant::Destructive,
                on_click: move |_| confirm_erase.set(true),
                icon_left: rsx! { lucide_dioxus::Trash2 { class: "w-3.5 h-3.5" } },
                "Erase All"
            }
        }

        AlertDialogRoot {
            open: *confirm_erase.read(),
            on_open_change: move |v: bool| confirm_erase.set(v),
            class: "fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm",

            AlertDialogContent {
                class: "bg-card border border-border rounded-lg shadow-2xl p-6 max-w-sm mx-4",

                AlertDialogTitle { class: "text-lg font-semibold mb-2", "Erase flash memory" }
                AlertDialogDescription {
                    class: "text-sm text-muted-foreground mb-4",
                    "This will erase the entire flash memory on the device. All firmware and data will be lost. This cannot be undone."
                }
                AlertDialogActions {
                    class: "flex justify-end gap-2",
                    AlertDialogCancel {
                        class: "px-3 py-1.5 rounded-lg border border-border text-sm hover:bg-muted/50 transition-colors",
                        "Cancel"
                    }
                    AlertDialogAction {
                        class: "px-3 py-1.5 rounded-lg bg-destructive text-destructive-foreground text-sm hover:bg-destructive/90 transition-colors",
                        on_click: move |_| controller.erase(),
                        "Erase All"
                    }
                }
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
