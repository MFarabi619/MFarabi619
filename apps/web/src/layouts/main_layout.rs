use crate::{Route, brand, components::navbar::Navbar};
use dioxus::prelude::*;
use dioxus_router::{Outlet, use_route};
use ui::components::toast::ToastProvider;

#[component]
pub fn MainLayout() -> Element {
    let route = use_route::<Route>();
    let name = brand::ACTIVE.name;
    let title = match route {
        Route::Landing { .. } => name.to_string(),
        Route::Dashboard { .. } => format!("Dashboard — {name}"),
        Route::Canopeo { .. } => format!("Canopeo — {name}"),
        Route::Docs { .. } => format!("{name} — Docs"),
        Route::Err404 { .. } => format!("{name} — 404"),
        _ => name.to_string(),
    };

    let chip_model = use_signal(String::new);
    let heap_memory = use_signal(String::new);
    let device_ctx = use_context_provider(|| crate::DeviceContext {
        chip_model,
        heap_memory,
    });
    let is_landing = matches!(route, Route::Landing { .. });
    let is_docs = matches!(route, Route::Docs { .. });

    rsx! {
        document::Title { "{title}" }
        ToastProvider {
        div {
            class: "min-h-screen overflow-x-hidden bg-background text-foreground font-sans relative",

            div {
                class: "fixed inset-0 blur-[120px] saturate-[140%] opacity-60 pointer-events-none z-0",
                aria_hidden: "true",
                div {
                    class: "absolute w-[60vmax] h-[60vmax] rounded-full opacity-60 mix-blend-screen \
                            will-change-[transform,opacity] \
                            animate-[float_25s_ease-in-out_infinite_alternate] \
                            [animation-delay:-6s] \
                            top-[-20%] left-[-15%]",
                    style: "background: radial-gradient(circle, var(--aura-1), transparent 70%);",
                }
                div {
                    class: "absolute w-[60vmax] h-[60vmax] rounded-full opacity-60 mix-blend-screen \
                            will-change-[transform,opacity] \
                            animate-[float_25s_ease-in-out_infinite_alternate] \
                            [animation-delay:-12s] \
                            top-[-8%] left-[75%]",
                    style: "background: radial-gradient(circle, var(--aura-2), transparent 70%);",
                }
                div {
                    class: "absolute w-[60vmax] h-[60vmax] rounded-full opacity-60 mix-blend-screen \
                            will-change-[transform,opacity] \
                            animate-[float_25s_ease-in-out_infinite_alternate] \
                            [animation-delay:-18s] \
                            top-[75%] left-[40%]",
                    style: "background: radial-gradient(circle, var(--aura-3), transparent 70%);",
                }
            }

            div { class: "relative z-10 flex flex-col min-h-screen",
                Navbar {
                    on_search: move |_| *crate::SHOW_COMMAND_PALETTE.write() = true,
                    on_network: move |_| {
                        *crate::SHOW_NETWORK_SHEET.write() = true;
                    },
                    chip_model: device_ctx.chip_model.read().clone(),
                    heap_memory: device_ctx.heap_memory.read().clone(),
                    is_landing,
                }

                main {
                    class: if is_landing || is_docs {
                        "flex-1 pt-16"
                    } else {
                        "flex-1 mx-auto w-[min(100%-24px,980px)] pt-24 pb-4"
                    },
                    Outlet::<Route> {}
                }

                footer { class: "mt-20 py-6 text-center text-sm text-gray-300/80",
                    p {
                        class: "w-fit mx-auto bg-[linear-gradient(90deg,#ffd200_0%,#ec8c78_33%,#e779c1_67%,#58c7f3_100%)] bg-clip-text text-transparent",
                        "© 2026 {name}."
                    }
                    div { class: "mt-2 inline-flex items-center gap-2 flex-wrap justify-center",
                        span { "Made by " }
                        a {
                            class: "text-rose-400 hover:text-primary hover:underline transition-colors",
                            href: "{brand::ACTIVE.attribution_url}",
                            target: "_blank",
                            rel: "noopener noreferrer",
                            "{brand::ACTIVE.attribution_name}"
                        }
                        span { " with " }
                        a {
                            href: "https://nixos.org",
                            target: "_blank",
                            rel: "noopener noreferrer",
                            title: "NixOS",
                            img { class: "inline w-5", src: "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/icons/nix.svg" }
                        }
                        span { ", " }
                        a {
                            href: "https://rust-lang.org",
                            target: "_blank",
                            rel: "noopener noreferrer",
                            title: "Rust",
                            img { class: "inline w-5", src: "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/icons/rust-symbol.svg" }
                        }
                        span { "," }
                        a {
                            href: "https://dioxuslabs.com",
                            target: "_blank",
                            rel: "noopener noreferrer",
                            title: "Dioxus",
                            img { class: "inline w-6", src: "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/icons/dioxus-multiplatform-animated.svg" }
                        }
                        span { ", & " }
                        a {
                            href: "https://lumenblocks.dev",
                            target: "_blank",
                            rel: "noopener noreferrer",
                            title: "Lumen",
                            img { class: "inline w-5", src: "https://lumenblocks.dev/assets/lumen-logo-small-dxh104608121b07667.png" }
                        }
                    }
                }
            }
        }
        }
    }
}
