use crate::Route;
use crate::components::navbar::Navbar;
use dioxus::prelude::*;
use dioxus_router::{Outlet, use_route};
use ui::components::toast::ToastProvider;

#[component]
pub fn MainLayout() -> Element {
    let route = use_route::<Route>();
    let title = match route {
        Route::Home { .. } => "Apidae Systems",
        Route::Docs { .. } => "Apidae Systems - Docs",
        Route::Err404 { .. } => "Apidae Systems - 404",
    };

    rsx! {
        document::Title { "{title}" }
        ToastProvider {
        div { class: "min-h-screen relative",
            Navbar {
                on_search: move |_| *crate::SHOW_COMMAND_PALETTE.write() = true,
                chip_model: crate::DEVICE_CHIP_MODEL.read().clone(),
                uptime: crate::DEVICE_UPTIME.read().clone(),
                heap_free: crate::DEVICE_HEAP_FREE.read().clone(),
            }

            main { class: "mx-auto w-[min(100%-24px,980px)] py-4",
                Outlet::<Route> {}
            }
        }
        }
    }
}
