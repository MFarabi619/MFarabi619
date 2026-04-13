use super::file_icon;
use crate::api;
use crate::api::{DeviceStatusData, FileEntry};
use crate::services::FileService;
use dioxus::html::HasFileData;
use dioxus::prelude::*;
use dioxus_primitives::alert_dialog::{
    AlertDialogAction, AlertDialogActions, AlertDialogCancel, AlertDialogContent,
    AlertDialogDescription, AlertDialogRoot, AlertDialogTitle,
};
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
    let mut pending_delete: Signal<Option<(String, String)>> = use_signal(|| None);

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
            div {
                class: "border border-border rounded-lg overflow-hidden p-3 transition-colors",
                ondragover: move |e| { e.prevent_default(); },
                ondrop: move |e| async move {
                    e.prevent_default();
                    for file in e.files() {
                        let name = file.name();
                        match file.read_bytes().await {
                            Ok(bytes) => {
                                let url = device_url.read().clone();
                                match FileService::upload(&url, "sd", &name, &bytes).await {
                                    Ok(resp) if resp.status().is_success() => {
                                        toasts.success(format!("Uploaded {}", name), None);
                                        if let Ok(entries) = FileService::list(&url, "sd").await {
                                            files.set(entries);
                                        }
                                    }
                                    _ => toasts.error(format!("Upload failed: {}", name), None),
                                }
                            }
                            Err(_) => toasts.error(format!("Failed to read {}", name), None),
                        }
                    }
                },
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
                                        aria_label: "Download {filename}",
                                        href: "{device}/api/filesystem/sd/{filename_for_download}",
                                        target: "_blank",
                                        Download { class: "w-3.5 h-3.5" }
                                    }
                                    button {
                                        class: "p-1 rounded hover:bg-destructive/20 text-destructive",
                                        aria_label: "Delete {filename}",
                                        onclick: move |_| {
                                            pending_delete.set(Some(("sd".into(), filename_for_delete.clone())));
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
                                        aria_label: "Delete {filename}",
                                        onclick: move |_| {
                                            pending_delete.set(Some(("littlefs".into(), filename_for_delete.clone())));
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

            input {
                id: "sd-upload-input",
                r#type: "file",
                class: "hidden",
                onchange: move |evt| async move {
                    for file in evt.files() {
                        let name = file.name();
                        match file.read_bytes().await {
                            Ok(bytes) => {
                                let url = device_url.read().clone();
                                match FileService::upload(&url, "sd", &name, &bytes).await {
                                    Ok(resp) if resp.status().is_success() => {
                                        toasts.success(format!("Uploaded {}", name), None);
                                        if let Ok(entries) = FileService::list(&url, "sd").await {
                                            files.set(entries);
                                        }
                                    }
                                    _ => toasts.error(format!("Upload failed: {}", name), None),
                                }
                            }
                            Err(_) => toasts.error(format!("Failed to read {}", name), None),
                        }
                    }
                },
            }

            {
                let is_open = pending_delete.read().is_some();
                let display_name = pending_delete.read().as_ref().map(|(_, n)| n.clone()).unwrap_or_default();
                rsx! {
                    AlertDialogRoot {
                        open: is_open,
                        on_open_change: move |v: bool| { if !v { pending_delete.set(None); } },
                        class: "fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm",

                        AlertDialogContent {
                            class: "bg-card border border-border rounded-lg shadow-2xl p-6 max-w-sm mx-4",

                            AlertDialogTitle { class: "text-lg font-semibold mb-2", "Delete file" }
                            AlertDialogDescription {
                                class: "text-sm text-muted-foreground mb-4",
                                "Are you sure you want to delete "
                                span { class: "font-mono text-foreground", "{display_name}" }
                                "? This cannot be undone."
                            }
                            AlertDialogActions {
                                class: "flex justify-end gap-2",
                                AlertDialogCancel {
                                    class: "px-3 py-1.5 rounded-lg border border-border text-sm hover:bg-muted/50 transition-colors",
                                    "Cancel"
                                }
                                AlertDialogAction {
                                    class: "px-3 py-1.5 rounded-lg bg-destructive text-destructive-foreground text-sm hover:bg-destructive/90 transition-colors",
                                    on_click: move |_| {
                                        if let Some((fs_type, name)) = pending_delete.read().clone() {
                                            let url = device_url.read().clone();
                                            spawn(async move {
                                                match FileService::delete(&url, &fs_type, &name).await {
                                                    Ok(response) if response.status().is_success() => {
                                                        toasts.success(format!("Deleted {name}"), None);
                                                        if fs_type == "sd" {
                                                            if let Ok(entries) = FileService::list(&url, "sd").await {
                                                                files.set(entries);
                                                            }
                                                        } else {
                                                            if let Ok(entries) = FileService::list(&url, "littlefs").await {
                                                                littlefs_files.set(entries);
                                                            }
                                                        }
                                                    }
                                                    _ => toasts.error(format!("Failed to delete {name}"), None),
                                                }
                                            });
                                        }
                                    },
                                    "Delete"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
