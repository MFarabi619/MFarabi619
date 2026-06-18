use dioxus::prelude::*;
use lucide_dioxus::{Database, File, FileCode, FileSpreadsheet, FileText, Image};

pub fn file_icon(name: &str) -> Element {
    let extension = name.rsplit('.').next().unwrap_or("").to_ascii_lowercase();
    match extension.as_str() {
        "js" | "rs" | "css" | "toml" => rsx! { FileCode { class: "w-4 h-4 text-primary" } },
        "html" | "htm" => rsx! { FileCode { class: "w-4 h-4 text-chart-3" } },
        "svg" | "png" | "jpg" => rsx! { Image { class: "w-4 h-4 text-chart-2" } },
        "csv" | "tsv" => rsx! { FileSpreadsheet { class: "w-4 h-4 text-chart-4" } },
        "db" | "sqlite" => rsx! { Database { class: "w-4 h-4 text-chart-4" } },
        "txt" | "log" | "md" => rsx! { FileText { class: "w-4 h-4 text-muted-foreground" } },
        "wasm" | "was" => rsx! { FileCode { class: "w-4 h-4 text-chart-5" } },
        _ => rsx! { File { class: "w-4 h-4 text-muted-foreground" } },
    }
}

#[component]
pub fn LiveIndicator(connected: bool) -> Element {
    let (dot_class, ping_class, label) = if connected {
        ("bg-emerald-400", "absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-70 animate-ping", "LIVE")
    } else {
        ("bg-amber-500", "absolute inline-flex h-full w-full rounded-full bg-amber-500 opacity-70 animate-pulse", "POLLING")
    };
    rsx! {
        div { class: "flex items-center gap-2 rounded-full border border-border bg-background/60 px-3 py-1.5 text-xs text-muted-foreground shrink-0",
            span { class: "relative flex h-2 w-2",
                span { class: "{ping_class}" }
                span { class: "relative inline-flex h-2 w-2 rounded-full {dot_class}" }
            }
            span { class: "font-medium text-foreground", "{label}" }
        }
    }
}

#[component]
pub fn StatusBadge(icon: Element, value: String) -> Element {
    rsx! {
        span { class: "inline-flex items-center gap-1.5 rounded-full border border-border bg-background/60 px-2.5 py-1 text-xs font-mono text-foreground",
            {icon}
            "{value}"
        }
    }
}

#[component]
pub fn Th(children: Element) -> Element {
    rsx! {
        th { scope: "col", class: "text-left px-3 py-2 border-b border-border text-muted-foreground text-xs uppercase tracking-wider sticky top-0 bg-muted whitespace-nowrap",
            {children}
        }
    }
}

#[component]
pub fn Td(children: Element, class: Option<String>) -> Element {
    let extra = class.unwrap_or_default();
    rsx! {
        td { class: "px-3 py-2 text-sm {extra}", {children} }
    }
}
