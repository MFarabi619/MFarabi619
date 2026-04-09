use crate::api::{self, DeviceStatusData, FileEntry};
use super::file_icon;
use dioxus::prelude::*;
use lucide_dioxus::{Download, HardDrive, Plus, Trash2};
use ui::components::progress::{Progress, ProgressVariant};
use ui::components::toast::Toasts;

#[component]
pub fn FilesystemPanel(
    device_url: Signal<String>,
    files: Signal<Vec<FileEntry>>,
    littlefs_files: Signal<Vec<FileEntry>>,
    littlefs_total_bytes: Signal<u64>,
    littlefs_used_bytes: Signal<u64>,
    status: Signal<Option<DeviceStatusData>>,
    storage_percent: Memo<f64>,
) -> Element {
    let toasts = Toasts;
    let mut show_toast = move |message: String, kind: &'static str| {
        match kind {
            "ok" => toasts.success(message, None),
            "err" => toasts.error(message, None),
            "warn" => toasts.warning(message, None),
            _ => toasts.info(message, None),
        }
    };

    let status_data = status.read();

    rsx! {
        section { id: "filesystem-section", class: "panel-shell-strong p-4",
            h2 { class: "mb-3 text-xl font-semibold", "Filesystem" }

            // SD Card
            div { class: "border border-border rounded-2xl overflow-hidden p-3",
                div { class: "flex items-center gap-2 mb-1",
                    HardDrive { class: "w-5 h-5 text-primary" }
                    span { class: "font-semibold", "SD Card" }
                    if let Some(ref device_status) = *status_data {
                        span { class: "text-xs text-muted-foreground ml-auto",
                            "{api::format_file_size(device_status.storage.used_bytes)} / {api::format_file_size(device_status.storage.total_bytes)}"
                        }
                    }
                }

                if status_data.is_some() {
                    div { class: "mb-3",
                        Progress {
                            value: storage_percent,
                            max: 100.0,
                            variant: if storage_percent() > 90.0 { ProgressVariant::Destructive } else if storage_percent() > 70.0 { ProgressVariant::Warning } else { ProgressVariant::Success },
                        }
                    }
                }

                for file in files.read().iter() {
                    {
                        let filename = file.name.clone();
                        let file_size = file.size;
                        let filename_for_delete = filename.clone();
                        let filename_for_download = filename.clone();
                        let device = device_url.read().clone();
                        rsx! {
                            div { class: "flex items-center gap-2 py-2 group",
                                {file_icon(&filename)}
                                span { class: "text-sm font-mono text-foreground truncate", "{filename}" }
                                span { class: "text-xs text-muted-foreground shrink-0 ml-auto", "{api::format_file_size(file_size)}" }
                                a {
                                    class: "opacity-0 group-hover:opacity-100 transition-opacity p-1 rounded hover:bg-accent/40 text-muted-foreground",
                                    href: "{device}/api/filesystem/file/{filename_for_download}?location=sd",
                                    target: "_blank",
                                    Download { class: "w-3.5 h-3.5" }
                                }
                                button {
                                    class: "opacity-0 group-hover:opacity-100 transition-opacity p-1 rounded hover:bg-destructive/20 text-destructive",
                                    onclick: move |_| {
                                        let url = device_url.read().clone();
                                        let name = filename_for_delete.clone();
                                        spawn(async move {
                                            match api::delete_file(&url, "sd", &name).await {
                                                Ok(response) if response.status().is_success() => {
                                                    show_toast(format!("Deleted {name}"), "ok");
                                                    if let Ok(entries) = api::fetch_filesystem(&url, "sd").await {
                                                        files.set(entries);
                                                    }
                                                }
                                                _ => show_toast(format!("Failed to delete {name}"), "err"),
                                            }
                                        });
                                    },
                                    Trash2 { class: "w-3.5 h-3.5" }
                                }
                            }
                        }
                    }
                }

                button {
                    class: "mt-2 w-full py-2 rounded-2xl border border-dashed border-border text-sm text-muted-foreground hover:bg-muted/30 transition-colors flex items-center justify-center gap-1",
                    onclick: move |_| {
                        document::eval("document.getElementById('sd-upload-input')?.click()");
                    },
                    Plus { class: "w-3.5 h-3.5" }
                    "Add file..."
                }
            }

            // LittleFS
            div { class: "mt-3 border border-border rounded-2xl overflow-hidden p-3",
                div { class: "flex items-center gap-2 mb-1",
                    HardDrive { class: "w-5 h-5 text-primary" }
                    span { class: "font-semibold", "LittleFS" }
                    if *littlefs_total_bytes.read() > 0 {
                        span { class: "text-xs text-muted-foreground ml-auto",
                            "{api::format_file_size(*littlefs_used_bytes.read())} / {api::format_file_size(*littlefs_total_bytes.read())}"
                        }
                    }
                }

                if *littlefs_total_bytes.read() > 0 {
                    {
                        let littlefs_percent = (*littlefs_used_bytes.read() as f64 / *littlefs_total_bytes.read() as f64 * 100.0).clamp(0.0, 100.0);
                        let littlefs_percent_signal = use_signal(move || littlefs_percent);
                        rsx! {
                            div { class: "mb-3",
                                Progress {
                                    value: littlefs_percent_signal,
                                    max: 100.0,
                                    variant: if littlefs_percent > 90.0 { ProgressVariant::Destructive } else if littlefs_percent > 70.0 { ProgressVariant::Warning } else { ProgressVariant::Success },
                                }
                            }
                        }
                    }
                }

                if littlefs_files.read().is_empty() {
                    p { class: "text-sm text-muted-foreground", "No files found." }
                }

                for file in littlefs_files.read().iter() {
                    {
                        let filename = file.name.clone();
                        let file_size = file.size;
                        let filename_for_delete = filename.clone();
                        rsx! {
                            div { class: "flex items-center gap-2 py-2 group",
                                {file_icon(&filename)}
                                span { class: "text-sm font-mono text-foreground truncate", "{filename}" }
                                span { class: "text-xs text-muted-foreground shrink-0 ml-auto", "{api::format_file_size(file_size)}" }
                                button {
                                    class: "opacity-0 group-hover:opacity-100 transition-opacity p-1 rounded hover:bg-destructive/20 text-destructive",
                                    onclick: move |_| {
                                        let url = device_url.read().clone();
                                        let name = filename_for_delete.clone();
                                        spawn(async move {
                                            match api::delete_file(&url, "littlefs", &name).await {
                                                Ok(response) if response.status().is_success() => {
                                                    show_toast(format!("Deleted {name}"), "ok");
                                                    if let Ok(entries) = api::fetch_filesystem(&url, "littlefs").await {
                                                        littlefs_files.set(entries);
                                                    }
                                                }
                                                _ => show_toast(format!("Failed to delete {name}"), "err"),
                                            }
                                        });
                                    },
                                    Trash2 { class: "w-3.5 h-3.5" }
                                }
                            }
                        }
                    }
                }

                button {
                    class: "mt-2 w-full py-2 rounded-2xl border border-dashed border-border text-sm text-muted-foreground hover:bg-muted/30 transition-colors flex items-center justify-center gap-1",
                    Plus { class: "w-3.5 h-3.5" }
                    "Add file..."
                }
            }

            // Hidden file input
            input {
                id: "sd-upload-input",
                r#type: "file",
                class: "hidden",
                onchange: move |_| {
                    show_toast("File upload — use curl for now".into(), "warn");
                },
            }
        }
    }
}
