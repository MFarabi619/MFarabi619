use crate::APIDAE_SYMBOL;
use crate::Route;
use dioxus::prelude::*;
use lucide_dioxus::{Cpu, MemoryStick, Search, Wifi};

#[component]
pub fn Navbar(
    on_search: EventHandler<()>,
    on_network: EventHandler<()>,
    chip_model: String,
    heap_free: String,
) -> Element {
    rsx! {
        header {
            class: "sticky top-0 z-20 border-b border-border bg-background/60 backdrop-blur-md",
            div {
                class: "mx-auto w-[min(100%-24px,980px)] grid grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)] items-center gap-3 min-h-[62px]",

                // Left: logo
                Link {
                    to: Route::Home {},
                    class: "inline-flex items-center gap-2 text-foreground no-underline font-semibold",
                    img { class: "w-7 h-7", src: APIDAE_SYMBOL }
                    span { "Apidae Systems" }
                }

                // Center: search
                button {
                    r#type: "button",
                    class: "px-3 py-1.5 rounded-lg border border-border bg-background/50 text-foreground text-sm flex items-center gap-2 transition-colors duration-200 ease-in-out hover:bg-muted/70 hover:border-accent",
                    onclick: move |_| on_search.call(()),
                    Search { class: "w-4 h-4 text-muted-foreground" }
                    span { class: "text-muted-foreground", "Search..." }
                    span { class: "text-xs text-muted-foreground bg-muted px-1.5 py-0.5 rounded", "Ctrl+K" }
                }

                // Right: device status badges
                div { class: "justify-self-end inline-flex items-center gap-2",
                    if !chip_model.is_empty() {
                        span { class: "inline-flex items-center gap-1.5 rounded-full border border-border bg-background/60 px-2.5 py-1 text-xs font-mono text-foreground",
                            Cpu { class: "w-3.5 h-3.5" }
                            "{chip_model}"
                        }
                        span { class: "inline-flex items-center gap-1.5 rounded-full border border-border bg-background/60 px-2.5 py-1 text-xs font-mono text-foreground",
                            MemoryStick { class: "w-3.5 h-3.5" }
                            "{heap_free}"
                        }
                    } else {
                        span { class: "inline-flex items-center gap-1.5 rounded-full border border-border bg-background/60 px-2.5 py-1",
                            div { class: "w-3.5 h-3.5 bg-muted rounded animate-pulse" }
                            div { class: "w-16 h-3.5 bg-muted rounded animate-pulse" }
                        }
                        span { class: "inline-flex items-center gap-1.5 rounded-full border border-border bg-background/60 px-2.5 py-1",
                            div { class: "w-3.5 h-3.5 bg-muted rounded animate-pulse" }
                            div { class: "w-20 h-3.5 bg-muted rounded animate-pulse" }
                        }
                    }
                    button {
                        class: "inline-flex items-center gap-1.5 rounded-full border border-border bg-background/60 px-2.5 py-1 text-xs font-mono text-foreground hover:bg-muted/50 transition-colors cursor-pointer",
                        onmouseenter: move |_| on_network.call(()),
                        Wifi { class: "w-3.5 h-3.5" }
                    }
                }
            }
        }
    }
}
