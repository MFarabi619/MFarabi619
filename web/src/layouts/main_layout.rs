use crate::Route;
use crate::APIDAE_SYMBOL;
use crate::components::navbar::Navbar;
use dioxus::prelude::*;
use dioxus_router::{Outlet, use_route};
use lucide_dioxus::{Github, Globe, Linkedin};
use ui::components::toast::ToastProvider;

#[component]
pub fn MainLayout() -> Element {
    let route = use_route::<Route>();
    let title = match route {
        Route::Home { .. } => "Apidae Systems",
        Route::Docs { .. } => "Apidae Systems - Docs",
        Route::Err404 { .. } => "Apidae Systems - 404",
        _ => "Apidae Systems",
    };

    rsx! {
        document::Title { "{title}" }
        ToastProvider {
        div { class: "min-h-screen relative flex flex-col",
            Navbar {
                on_search: move |_| *crate::SHOW_COMMAND_PALETTE.write() = true,
                on_network: move |_| {
                    *crate::SHOW_NETWORK_SHEET.write() = true;
                },
                chip_model: crate::DEVICE_CHIP_MODEL.read().clone(),
                heap_free: crate::DEVICE_HEAP_FREE.read().clone(),
            }

            main { class: "mx-auto w-[min(100%-24px,980px)] py-4 flex-1",
                Outlet::<Route> {}
            }

            footer { class: "border-t border-border bg-background/60 backdrop-blur-md mt-8",
                div { class: "mx-auto w-[min(100%-24px,980px)] py-6 flex flex-col sm:flex-row items-center justify-between gap-4",
                    div { class: "flex items-center gap-2 text-sm text-muted-foreground",
                        img { class: "w-5 h-5", src: APIDAE_SYMBOL }
                        "Apidae Systems"
                    }
                    div { class: "flex items-center gap-4",
                        a {
                            class: "text-muted-foreground hover:text-foreground transition-colors",
                            href: "https://www.apidaesystems.ca",
                            target: "_blank",
                            title: "Website",
                            Globe { class: "w-5 h-5" }
                        }
                        a {
                            class: "text-muted-foreground hover:text-foreground transition-colors",
                            href: "https://www.linkedin.com/company/apidae-systems/",
                            target: "_blank",
                            title: "LinkedIn",
                            Linkedin { class: "w-5 h-5" }
                        }
                        a {
                            class: "text-muted-foreground hover:text-foreground transition-colors",
                            href: "https://github.com/apidae-systems",
                            target: "_blank",
                            title: "GitHub",
                            Github { class: "w-5 h-5" }
                        }
                    }
                }
            }
        }
        }
    }
}
