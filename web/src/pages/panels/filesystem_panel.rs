use crate::api::{self, DeviceStatusData, FileEntry};
use super::file_icon;
use dioxus::prelude::*;
use lucide_dioxus::{Download, HardDrive, Plus, Trash2};
use ui::components::progress::{Progress, ProgressVariant};
use ui::components::toast::use_toast;

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
    let toasts = use_toast();

    let status_data = status.read();

    let littlefs_percent = use_memo(move || {
        let total = *littlefs_total_bytes.read();
        if total > 0 {
            (*littlefs_used_bytes.read() as f64 / total as f64 * 100.0).clamp(0.0, 100.0)
        } else {
            0.0
        }
    });

    rsx! {
        section { id: "filesystem-section", class: "panel-shell-strong p-4",
            h2 { class: "mb-3 text-xl font-semibold", "Filesystem" }

            // SD Card
            div { class: "border border-border rounded-lg overflow-hidden p-3",
                div { class: "flex items-center gap-2 mb-1",
                    HardDrive { class: "w-5 h-5 text-primary" }
                    span { class: "font-semibold", "SD" }
                    if let Some(ref device_status) = *status_data {
                        span { class: "text-xs text-muted-foreground ml-auto",
                            "{api::format_storage_pair(device_status.storage.used_bytes, device_status.storage.total_bytes)}"
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

                if files.read().is_empty() && status_data.is_none() {
                    for _ in 0..3 {
                        div { class: "flex items-center gap-2 py-2",
                            div { class: "w-4 h-4 bg-muted rounded animate-pulse" }
                            div { class: "h-4 flex-1 bg-muted rounded animate-pulse" }
                            div { class: "h-4 w-14 bg-muted rounded animate-pulse" }
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
                            div { key: "{filename}", class: "flex items-center gap-2 py-2 group relative",
                                {file_icon(&filename)}
                                span { class: "text-sm font-mono text-foreground truncate flex-1", "{filename}" }
                                span { class: "text-xs text-muted-foreground shrink-0 ml-auto tabular-nums transition-opacity duration-200 ease-in-out opacity-100 group-hover:opacity-0", "{api::format_file_size(file_size)}" }
                                div { class: "flex items-center gap-0.5 shrink-0 ml-auto absolute right-0 transition-opacity duration-200 ease-in-out opacity-0 group-hover:opacity-100",
                                    a {
                                        class: "p-1 rounded hover:bg-accent/40 text-muted-foreground",
                                        href: "{device}/api/filesystem/file/{filename_for_download}?location=sd",
                                        target: "_blank",
                                        Download { class: "w-3.5 h-3.5" }
                                    }
                                    button {
                                        class: "p-1 rounded hover:bg-destructive/20 text-destructive",
                                        onclick: move |_| {
                                            let url = device_url.read().clone();
                                            let name = filename_for_delete.clone();
                                            spawn(async move {
                                                match api::delete_file(&url, "sd", &name).await {
                                                    Ok(response) if response.status().is_success() => {
                                                        toasts.success(format!("Deleted {name}"), None);
                                                        if let Ok(entries) = api::fetch_filesystem(&url, "sd").await {
                                                            files.set(entries);
                                                        }
                                                    }
                                                    _ => toasts.error(format!("Failed to delete {name}"), None),
                                                }
                                            });
                                        },
                                        Trash2 { class: "w-3.5 h-3.5" }
                                    }
                                }
                            }
                        }
                    }
                }

                label {
                    r#for: "sd-upload-input",
                    class: "mt-2 w-full py-2 rounded-lg border border-dashed border-border text-sm text-muted-foreground hover:bg-muted/30 transition-colors flex items-center justify-center gap-1 cursor-pointer",
                    Plus { class: "w-3.5 h-3.5" }
                    "Add file..."
                }
            }

            // LittleFS
            div { class: "mt-3 border border-border rounded-lg overflow-hidden p-3",
                div { class: "flex items-center gap-2 mb-1",
                    HardDrive { class: "w-5 h-5 text-primary" }
                    span { class: "font-semibold", "LittleFS" }
                    if *littlefs_total_bytes.read() > 0 {
                        span { class: "text-xs text-muted-foreground ml-auto",
                            "{api::format_storage_pair(*littlefs_used_bytes.read(), *littlefs_total_bytes.read())}"
                        }
                    }
                }

                if *littlefs_total_bytes.read() > 0 {
                    {
                        let pct = *littlefs_percent.read();
                        let variant = if pct > 90.0 { ProgressVariant::Destructive } else if pct > 70.0 { ProgressVariant::Warning } else { ProgressVariant::Success };
                        rsx! {
                            div { class: "mb-3",
                                Progress {
                                    value: littlefs_percent,
                                    max: 100.0,
                                    variant: variant,
                                }
                            }
                        }
                    }
                }

                if littlefs_files.read().is_empty() && status_data.is_none() {
                    for _ in 0..2 {
                        div { class: "flex items-center gap-2 py-2",
                            div { class: "w-4 h-4 bg-muted rounded animate-pulse" }
                            div { class: "h-4 flex-1 bg-muted rounded animate-pulse" }
                            div { class: "h-4 w-14 bg-muted rounded animate-pulse" }
                        }
                    }
                }

                for file in littlefs_files.read().iter() {
                    {
                        let filename = file.name.clone();
                        let file_size = file.size;
                        let filename_for_delete = filename.clone();
                        rsx! {
                            div { key: "{filename}", class: "flex items-center gap-2 py-2 group relative",
                                {file_icon(&filename)}
                                span { class: "text-sm font-mono text-foreground truncate flex-1", "{filename}" }
                                span { class: "text-xs text-muted-foreground shrink-0 ml-auto tabular-nums transition-opacity duration-200 ease-in-out opacity-100 group-hover:opacity-0", "{api::format_file_size(file_size)}" }
                                div { class: "flex items-center gap-0.5 shrink-0 ml-auto absolute right-0 transition-opacity duration-200 ease-in-out opacity-0 group-hover:opacity-100",
                                    button {
                                        class: "p-1 rounded hover:bg-destructive/20 text-destructive",
                                        onclick: move |_| {
                                            let url = device_url.read().clone();
                                            let name = filename_for_delete.clone();
                                            spawn(async move {
                                                match api::delete_file(&url, "littlefs", &name).await {
                                                    Ok(response) if response.status().is_success() => {
                                                        toasts.success(format!("Deleted {name}"), None);
                                                        if let Ok(entries) = api::fetch_filesystem(&url, "littlefs").await {
                                                            littlefs_files.set(entries);
                                                        }
                                                    }
                                                    _ => toasts.error(format!("Failed to delete {name}"), None),
                                                }
                                            });
                                        },
                                        Trash2 { class: "w-3.5 h-3.5" }
                                    }
                                }
                            }
                        }
                    }
                }

                button {
                    class: "mt-2 w-full py-2 rounded-lg border border-dashed border-border text-sm text-muted-foreground hover:bg-muted/30 transition-colors flex items-center justify-center gap-1",
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
                    toasts.warning("File upload \u{2014} use curl for now".into(), None);
                },
            }
        }
    }
}
