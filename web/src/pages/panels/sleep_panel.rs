use crate::api::DeviceStatusData;
use crate::services::DeviceService;
use dioxus::prelude::*;
use ui::components::switch::Switch;
use ui::components::toast::use_toast;
use super::shared_ui::StatusBadge;

const PRESETS: &[(u64, &str)] = &[
    (60, "1m"),
    (300, "5m"),
    (900, "15m"),
    (3600, "1h"),
];

#[component]
pub fn SleepPanel(
    device_url: Signal<String>,
    status: Signal<Option<DeviceStatusData>>,
) -> Element {
    let toasts = use_toast();
    let mut enabled = use_signal(|| false);
    let mut duration = use_signal(|| 300u64);
    let mut custom_active = use_signal(|| false);
    let mut custom_h = use_signal(String::new);
    let mut custom_m = use_signal(String::new);
    let mut custom_s = use_signal(String::new);
    let mut dirty = use_signal(|| false);
    let mut saving = use_signal(|| false);

    let mut sync_hms_from_duration = move |secs: u64| {
        custom_h.set((secs / 3600).to_string());
        custom_m.set(((secs % 3600) / 60).to_string());
        custom_s.set((secs % 60).to_string());
    };

    let mut recompute_duration = move || {
        let h = custom_h.read().trim().parse::<u64>().unwrap_or(0);
        let m = custom_m.read().trim().parse::<u64>().unwrap_or(0);
        let s = custom_s.read().trim().parse::<u64>().unwrap_or(0);
        duration.set(h * 3600 + m * 60 + s);
    };

    use_effect(move || {
        let snapshot = status.read().clone();
        if *dirty.read() {
            return;
        }

        if let Some(snapshot) = snapshot {
            enabled.set(snapshot.sleep.enabled);
            let secs = snapshot.sleep.default_duration_seconds;
            duration.set(secs);
            if PRESETS.iter().any(|(s, _)| *s == secs) {
                custom_active.set(false);
            } else {
                custom_active.set(true);
                sync_hms_from_duration(secs);
            }
        }
    });

    let snapshot = status.read().clone();
    let is_custom = *custom_active.read();

    rsx! {
        section { id: "sleep-panel", class: "panel-shell-strong p-4",
            div { class: "flex items-center justify-between gap-3",
                div { class: "flex items-center gap-3",
                    h2 { class: "text-xl font-semibold", "Deep Sleep" }
                    if let Some(snapshot) = snapshot.as_ref() {
                        StatusBadge {
                            icon: rsx! { span { class: "block h-2 w-2 rounded-full bg-amber-400" } },
                            value: snapshot.sleep.wake_cause.clone()
                        }
                    }
                }
                div { class: "flex items-center gap-3",
                    div { class: "flex items-center rounded-lg overflow-hidden border border-border",
                        for &(secs, label) in PRESETS {
                            {
                                let is_active = !is_custom && *duration.read() == secs;
                                rsx! {
                                    button {
                                        key: "{secs}",
                                        class: if is_active {
                                            "px-2.5 py-1.5 text-xs font-mono bg-primary text-primary-foreground"
                                        } else {
                                            "px-2.5 py-1.5 text-xs font-mono bg-background text-foreground/70 hover:bg-muted/30"
                                        },
                                        onclick: move |_| {
                                            duration.set(secs);
                                            custom_active.set(false);
                                            dirty.set(true);
                                        },
                                        "{label}"
                                    }
                                }
                            }
                        }
                        button {
                            class: if is_custom {
                                "px-2.5 py-1.5 text-xs font-mono bg-primary text-primary-foreground"
                            } else {
                                "px-2.5 py-1.5 text-xs font-mono bg-background text-foreground/70 hover:bg-muted/30"
                            },
                            onclick: move |_| {
                                custom_active.set(true);
                                dirty.set(true);
                                sync_hms_from_duration(*duration.read());
                            },
                            "custom"
                        }
                    }
                    if is_custom {
                        div { class: "flex items-center",
                            input {
                                r#type: "number",
                                class: "gold-input w-7 px-0 py-1 text-xs font-mono text-center bg-background border border-border rounded-l",
                                aria_label: "Hours",
                                placeholder: "0",
                                value: custom_h.read().clone(),
                                oninput: move |e| {
                                    custom_h.set(e.value());
                                    recompute_duration();
                                    dirty.set(true);
                                },
                            }
                            span { class: "text-[10px] text-muted-foreground px-0.5", "h" }
                            input {
                                r#type: "number",
                                class: "gold-input w-7 px-0 py-1 text-xs font-mono text-center bg-background border border-border",
                                aria_label: "Minutes",
                                placeholder: "0",
                                value: custom_m.read().clone(),
                                oninput: move |e| {
                                    custom_m.set(e.value());
                                    recompute_duration();
                                    dirty.set(true);
                                },
                            }
                            span { class: "text-[10px] text-muted-foreground px-0.5", "m" }
                            input {
                                r#type: "number",
                                class: "gold-input w-7 px-0 py-1 text-xs font-mono text-center bg-background border border-border rounded-r",
                                aria_label: "Seconds",
                                placeholder: "0",
                                value: custom_s.read().clone(),
                                oninput: move |e| {
                                    custom_s.set(e.value());
                                    recompute_duration();
                                    dirty.set(true);
                                },
                            }
                            span { class: "text-[10px] text-muted-foreground pl-0.5", "s" }
                        }
                    }
                    Switch {
                        checked: enabled,
                        on_checked_change: move |value: bool| {
                            let duration_seconds = *duration.read();
                            if duration_seconds == 0 {
                                toasts.error("Sleep duration must be greater than 0".to_string(), None);
                                return;
                            }
                            let url = device_url.read().clone();
                            enabled.set(value);
                            dirty.set(true);
                            saving.set(true);
                            spawn(async move {
                                match DeviceService::update_sleep_config(&url, value, duration_seconds).await {
                                    Ok(response) if response.ok => {
                                        if let Ok(envelope) = DeviceService::get_status(&url).await {
                                            status.set(Some(envelope.data));
                                        }
                                        dirty.set(false);
                                        toasts.success("Deep sleep configuration saved".to_string(), None);
                                    }
                                    Ok(_) => toasts.error("Sleep config update failed".to_string(), None),
                                    Err(error) => toasts.error(format!("Sleep config update failed: {error}"), None),
                                }
                                saving.set(false);
                            });
                        }
                    }
                }
            }
        }
    }
}
