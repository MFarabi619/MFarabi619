use crate::Route;
use crate::brand;
use dioxus::prelude::*;
use lucide_dioxus::{Cpu, MemoryStick, Search, Wifi};
use ui::components::button::{Button, ButtonSize, ButtonVariant};

#[component]
pub fn Navbar(
    on_search: EventHandler<()>,
    on_network: EventHandler<()>,
    chip_model: String,
    heap_memory: String,
    is_landing: bool,
) -> Element {
    rsx! {
        nav {
            class: "backdrop-blur-xl shadow-md fixed top-0 left-0 w-full px-6 py-4 \
                    transition-all duration-300 z-50 \
                    hover:shadow-[0_0_25px_rgba(255,255,255,0.35)]",
            div {
                class: "max-w-7xl mx-auto flex items-center justify-between",

                Link {
                    to: Route::Landing {},
                    class: "py-2 rounded transition-all duration-300 hover:scale-110 hover:drop-shadow-[0_0_12px_rgba(234,239,44,0.8)]",
                    div { class: "flex items-center gap-2",
                        img { class: "h-8", src: brand::ACTIVE.logo }
                        span {
                            class: "text-xl font-bold",
                            style: "background: var(--hero-gradient); \
                                    -webkit-background-clip: text; \
                                    background-clip: text; \
                                    color: transparent;",
                            "{brand::ACTIVE.name}"
                        }
                    }
                }

                if is_landing {
                    div { class: "hidden md:flex items-center gap-6",
                        for link in brand::ACTIVE.nav_links.iter() {
                            a {
                                target: "_blank",
                                rel: "noopener noreferrer",
                                class: "text-foreground hover:text-primary transition-colors",
                                href: "{link.href}",
                                "{link.label}"
                            }
                        }
                    }
                } else {
                    div { class: "flex items-center gap-3",
                        Button {
                            variant: ButtonVariant::Outline,
                            size: ButtonSize::Small,
                            on_click: move |_| on_search.call(()),
                            icon_left: rsx! { Search { class: "w-4 h-4 text-muted-foreground" } },
                            span { class: "text-muted-foreground", "Search..." }
                            span { class: "text-xs text-muted-foreground bg-muted px-1.5 py-0.5 rounded", "Ctrl+K" }
                        }
                        if !chip_model.is_empty() {
                            span { class: "hidden lg:inline-flex items-center gap-1.5 rounded-full border border-border bg-background/60 px-2.5 py-1 text-xs font-mono text-foreground",
                                Cpu { class: "w-3.5 h-3.5" }
                                "{chip_model}"
                            }
                            span { class: "hidden lg:inline-flex items-center gap-1.5 rounded-full border border-border bg-background/60 px-2.5 py-1 text-xs font-mono text-foreground",
                                MemoryStick { class: "w-3.5 h-3.5" }
                                "{heap_memory}"
                            }
                        }
                        div {
                            onmouseenter: move |_| on_network.call(()),
                            Button {
                                variant: ButtonVariant::Ghost,
                                size: ButtonSize::Small,
                                is_icon_button: true,
                                aria_label: "Network settings".to_string(),
                                on_click: move |_| on_network.call(()),
                                Wifi { class: "w-3.5 h-3.5" }
                            }
                        }
                    }
                }
            }
        }
    }
}
