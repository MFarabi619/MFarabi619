use crate::api::DeviceStatusData;
use crate::services::DeviceService;
use dioxus::prelude::*;
use ui::components::input::Input;
use ui::components::switch::Switch;
use ui::components::toast::use_toast;
use super::shared_ui::StatusBadge;

#[component]
pub fn SleepPanel(
    device_url: Signal<String>,
    status: Signal<Option<DeviceStatusData>>,
) -> Element {
    let toasts = use_toast();
    let mut enabled = use_signal(|| false);
    let mut duration_input = use_signal(String::new);
    let mut dirty = use_signal(|| false);
    let mut saving = use_signal(|| false);

    use_effect(move || {
        let snapshot = status.read().clone();
        if *dirty.read() {
            return;
        }

        if let Some(snapshot) = snapshot {
            enabled.set(snapshot.sleep.enabled);
            duration_input.set(snapshot.sleep.default_duration_seconds.to_string());
        }
    });

    let snapshot = status.read().clone();

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
                    Input {
                        id: Some("sleep-duration-input-inline".to_string()),
                        class: Some("gold-input w-20 px-3 py-2 text-sm font-mono text-right".to_string()),
                        input_type: "number".to_string(),
                        aria_label: Some("Deep sleep duration in seconds".to_string()),
                        value: duration_input.read().clone(),
                        on_input: Some(Callback::new(move |event: FormEvent| {
                            duration_input.set(event.value());
                            dirty.set(true);
                        })),
                    }
                    Switch {
                        checked: enabled,
                        on_checked_change: move |value: bool| {
                            let duration_seconds = match duration_input.read().trim().parse::<u64>() {
                                Ok(parsed) if parsed > 0 => parsed,
                                _ => {
                                    toasts.error("Sleep duration must be greater than 0".to_string(), None);
                                    return;
                                }
                            };
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
