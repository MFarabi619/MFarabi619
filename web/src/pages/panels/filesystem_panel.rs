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
use dioxus_primitives::dialog::{DialogContent, DialogRoot};
use lucide_dioxus::{Download, HardDrive, Pencil, Plus, Trash2, X};
use ui::components::button::{Button, ButtonSize, ButtonVariant};
use ui::components::input::Input;
use ui::components::label::Label;
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
    let sd_upload_input_label = use_signal(|| Some("sd-upload-input".to_string()));
    let mut pending_delete: Signal<Option<(String, String)>> = use_signal(|| None);
    let mut pending_rename: Signal<Option<(String, String)>> = use_signal(|| None);
    let mut rename_input = use_signal(String::new);
    let mut preview_name: Signal<Option<String>> = use_signal(|| None);
    let mut preview_rows: Signal<Vec<Vec<String>>> = use_signal(Vec::new);

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
                                toasts.info(format!("Uploading {}...", name), None);
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
                        let filename_for_preview = filename.clone();
                        let filename_for_rename = filename.clone();
                        let filename_for_delete = filename.clone();
                        let filename_for_download = filename.clone();
                        let device = device_url.read().clone();
                        let is_previewable = filename.ends_with(".csv") || filename.ends_with(".tsv");
                        rsx! {
                            div { key: "{filename}", class: "flex items-center gap-2 py-2 group relative",
                                {file_icon(&filename)}
                                if is_previewable {
                                    span {
                                        class: "text-sm font-mono text-foreground truncate flex-1 cursor-pointer hover:underline",
                                        onclick: move |_| {
                                            let name = filename_for_preview.clone();
                                            let url = device_url.read().clone();
                                            spawn(async move {
                                                match FileService::read_text(&url, "sd", &name).await {
                                                    Ok(text) => {
                                                        let rows: Vec<Vec<String>> = text.lines()
                                                            .take(200)
                                                            .map(|line| line.split(',').map(|c| c.trim().to_string()).collect())
                                                            .collect();
                                                        preview_rows.set(rows);
                                                        preview_name.set(Some(name));
                                                    }
                                                    Err(_) => toasts.error("Failed to fetch file".to_string(), None),
                                                }
                                            });
                                        },
                                        "{filename}"
                                    }
                                } else {
                                    span { class: "text-sm font-mono text-foreground truncate flex-1", "{filename}" }
                                }
                                span { class: "text-xs text-muted-foreground shrink-0 ml-auto tabular-nums transition-opacity duration-200 ease-in-out opacity-100 group-hover:opacity-0", "{api::format_file_size(file_size)}" }
                                div { class: "flex items-center gap-0.5 shrink-0 ml-auto absolute right-0 transition-opacity duration-200 ease-in-out opacity-0 group-hover:opacity-100",
                                    a {
                                        class: "p-1 rounded hover:bg-accent/40 text-muted-foreground",
                                        aria_label: "Download {filename}",
                                        href: "{device}/api/filesystem/sd/{filename_for_download}",
                                        target: "_blank",
                                        Download { class: "w-3.5 h-3.5" }
                                    }
                                    Button {
                                        variant: ButtonVariant::Ghost,
                                        size: ButtonSize::Small,
                                        is_icon_button: true,
                                        class: "p-1".to_string(),
                                        aria_label: format!("Rename {filename}"),
                                        on_click: move |_| {
                                            rename_input.set(filename_for_rename.clone());
                                            pending_rename.set(Some(("sd".into(), filename_for_rename.clone())));
                                        },
                                        Pencil { class: "w-3.5 h-3.5" }
                                    }
                                    Button {
                                        variant: ButtonVariant::Destructive,
                                        size: ButtonSize::Small,
                                        is_icon_button: true,
                                        class: "p-1".to_string(),
                                        aria_label: format!("Delete {filename}"),
                                        on_click: move |_| {
                                            pending_delete.set(Some(("sd".into(), filename_for_delete.clone())));
                                        },
                                        Trash2 { class: "w-3.5 h-3.5" }
                                    }
                                }
                            }
                        }
                    }
                }

                Label {
                    for_id: sd_upload_input_label,
                    class: Some("mt-2 mb-0 w-full py-2 rounded-lg border border-dashed border-border text-sm text-muted-foreground hover:bg-muted/30 transition-colors flex items-center justify-center gap-1 cursor-pointer".to_string()),
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
                        let filename_for_rename = filename.clone();
                        let filename_for_delete = filename.clone();
                        rsx! {
                            div { key: "{filename}", class: "flex items-center gap-2 py-2 group relative",
                                {file_icon(&filename)}
                                span { class: "text-sm font-mono text-foreground truncate flex-1", "{filename}" }
                                span { class: "text-xs text-muted-foreground shrink-0 ml-auto tabular-nums transition-opacity duration-200 ease-in-out opacity-100 group-hover:opacity-0", "{api::format_file_size(file_size)}" }
                                div { class: "flex items-center gap-0.5 shrink-0 ml-auto absolute right-0 transition-opacity duration-200 ease-in-out opacity-0 group-hover:opacity-100",
                                    Button {
                                        variant: ButtonVariant::Ghost,
                                        size: ButtonSize::Small,
                                        is_icon_button: true,
                                        class: "p-1".to_string(),
                                        aria_label: format!("Rename {filename}"),
                                        on_click: move |_| {
                                            rename_input.set(filename_for_rename.clone());
                                            pending_rename.set(Some(("littlefs".into(), filename_for_rename.clone())));
                                        },
                                        Pencil { class: "w-3.5 h-3.5" }
                                    }
                                    Button {
                                        variant: ButtonVariant::Destructive,
                                        size: ButtonSize::Small,
                                        is_icon_button: true,
                                        class: "p-1".to_string(),
                                        aria_label: format!("Delete {filename}"),
                                        on_click: move |_| {
                                            pending_delete.set(Some(("littlefs".into(), filename_for_delete.clone())));
                                        },
                                        Trash2 { class: "w-3.5 h-3.5" }
                                    }
                                }
                            }
                        }
                    }
                }

                Button {
                    class: "mt-2 w-full py-2 border-dashed text-sm text-muted-foreground hover:bg-muted/30".to_string(),
                    variant: ButtonVariant::Outline,
                    disabled: true,
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
                                toasts.info(format!("Uploading {}...", name), None);
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

            // Delete confirmation modal
            {
                let is_open = pending_delete.read().is_some();
                let delete_fs = pending_delete.read().as_ref().map(|(f, _)| f.clone()).unwrap_or_default();
                let delete_name = pending_delete.read().as_ref().map(|(_, n)| n.clone()).unwrap_or_default();
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
                                span { class: "font-mono text-foreground", "{delete_name}" }
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
                                        let fs_type = delete_fs.clone();
                                        let name = delete_name.clone();
                                        if name.is_empty() { return; }
                                        let url = device_url.read().clone();
                                        toasts.info(format!("Deleting {name}..."), None);
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
                                    },
                                    "Delete"
                                }
                            }
                        }
                    }
                }
            }

            // Rename modal
            {
                let is_open = pending_rename.read().is_some();
                let rename_fs = pending_rename.read().as_ref().map(|(f, _)| f.clone()).unwrap_or_default();
                let rename_old = pending_rename.read().as_ref().map(|(_, n)| n.clone()).unwrap_or_default();
                rsx! {
                    AlertDialogRoot {
                        open: is_open,
                        on_open_change: move |v: bool| { if !v { pending_rename.set(None); } },
                        class: "fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm",

                        AlertDialogContent {
                            class: "bg-card border border-border rounded-lg shadow-2xl p-6 max-w-sm mx-4",

                            AlertDialogTitle { class: "text-lg font-semibold mb-2", "Rename file" }
                            AlertDialogDescription {
                                class: "text-sm text-muted-foreground mb-4",
                                "Rename "
                                span { class: "font-mono text-foreground", "{rename_old}" }
                                " to:"
                            }
                            Input {
                                class: Some("w-full font-mono text-sm mb-4".to_string()),
                                input_type: "text".to_string(),
                                aria_label: Some("New filename".to_string()),
                                value: rename_input.read().clone(),
                                on_input: Some(Callback::new(move |e: FormEvent| {
                                    rename_input.set(e.value());
                                })),
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
                                        let fs_type = rename_fs.clone();
                                        let old = rename_old.clone();
                                        let new_name = rename_input.read().trim().to_string();
                                        if new_name.is_empty() || new_name == old {
                                            return;
                                        }
                                        let url = device_url.read().clone();
                                        toasts.info(format!("Renaming {old} to {new_name}..."), None);
                                        spawn(async move {
                                            match FileService::rename(&url, &fs_type, &old, &new_name).await {
                                                Ok(response) if response.status().is_success() => {
                                                    toasts.success(format!("Renamed to {new_name}"), None);
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
                                                _ => toasts.error(format!("Failed to rename {old}"), None),
                                            }
                                        });
                                    },
                                    "Rename"
                                }
                            }
                        }
                    }
                }
            }
            // CSV preview modal
            {
                let is_preview_open = preview_name.read().is_some();
                let preview_filename = preview_name.read().clone().unwrap_or_default();
                let row_count = preview_rows.read().len().saturating_sub(1);
                rsx! {
                    DialogRoot {
                        open: is_preview_open,
                        on_open_change: move |v: bool| { if !v { preview_name.set(None); } },
                        class: "fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4",

                        DialogContent {
                            class: "w-full max-w-3xl bg-card border border-border rounded-lg shadow-2xl flex flex-col max-h-[80vh]",

                            div { class: "flex items-center justify-between px-5 py-4 border-b border-border",
                                div {
                                    h3 { class: "text-sm font-semibold font-mono", "{preview_filename}" }
                                    p { class: "text-xs text-muted-foreground", "{row_count} rows" }
                                }
                                Button {
                                    variant: ButtonVariant::Ghost,
                                    size: ButtonSize::Small,
                                    is_icon_button: true,
                                    aria_label: "Close".to_string(),
                                    on_click: move |_| preview_name.set(None),
                                    X { class: "w-5 h-5" }
                                }
                            }

                            div { class: "flex-1 overflow-auto",
                                table { class: "w-full text-xs font-mono",
                                    if let Some(header) = preview_rows.read().first() {
                                        thead {
                                            tr { class: "bg-muted sticky top-0",
                                                for cell in header.iter() {
                                                    th { class: "px-3 py-2 text-left text-muted-foreground whitespace-nowrap border-b border-border",
                                                        "{cell}"
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    tbody {
                                        for (i, row) in preview_rows.read().iter().skip(1).enumerate() {
                                            tr { key: "{i}", class: if i % 2 == 0 { "" } else { "bg-muted/30" },
                                                for cell in row.iter() {
                                                    td { class: "px-3 py-1.5 whitespace-nowrap", "{cell}" }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            div { class: "flex items-center gap-2 px-5 py-3 border-t border-border",
                                div { class: "flex-1" }
                                Button {
                                    variant: ButtonVariant::Outline,
                                    on_click: move |_| preview_name.set(None),
                                    "Close"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
