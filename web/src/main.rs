use dioxus::document;
use dioxus::prelude::*;

pub mod api;
mod components;
mod content;
mod layouts;
mod pages;

// Global signals for dialog state (shared between navbar and home page)
pub static SHOW_COMMAND_PALETTE: GlobalSignal<bool> = Signal::global(|| false);
pub static DEVICE_CHIP_MODEL: GlobalSignal<String> = Signal::global(String::new);
pub static DEVICE_UPTIME: GlobalSignal<String> = Signal::global(String::new);
pub static DEVICE_HEAP_FREE: GlobalSignal<String> = Signal::global(String::new);
pub static WIFI_SSID: GlobalSignal<String> = Signal::global(String::new);
pub static WIFI_RSSI: GlobalSignal<i32> = Signal::global(|| 0);
pub static WIFI_IP: GlobalSignal<String> = Signal::global(String::new);

use crate::content::docs;
use crate::layouts::{DocsLayout, MainLayout};
use crate::pages::{Err404, Home};

const BANNER_IMAGE: Asset = asset!("/assets/header.svg");
const TAILWIND_CSS: Asset = asset!("/assets/tailwind.css");
const FAVICON: Asset = asset!("/assets/symbol.svg");
const APIDAE_SYMBOL: Asset = asset!("/assets/symbol.svg");

#[derive(Clone, Routable, PartialEq, Eq, Debug)]
enum Route {
    #[layout(MainLayout)]
    #[route("/")]
    Home {},

    // ===== Docs =====
    #[layout(DocsLayout)]
    #[nest("/docs")]
    #[redirect("/", || Route::Docs {
        child: docs::router::BookRoute::Index { section: Default::default() }
    })]
    #[child("/")]
    Docs { child: docs::router::BookRoute },
    #[end_nest]
    #[end_layout]
    // ================
    #[layout(MainLayout)]
    #[route("/:..segments")]
    Err404 { segments: Vec<String> },
}

fn main() {
    dioxus::LaunchBuilder::new()
        .with_cfg(server_only! {
            ServeConfig::builder()
                .incremental(
                    dioxus::server::IncrementalRendererConfig::new()
                        .static_dir(
                            std::env::current_exe()
                                .unwrap()
                                .parent()
                                .unwrap()
                                .join("public")
                        )
                        .clear_cache(false)
                )
                .enable_out_of_order_streaming()
        })
        .launch(App);
}

#[component]
fn App() -> Element {
    rsx! {
        document::Link { rel: "icon", href: FAVICON }
        document::Link { rel: "manifest", href: "/assets/manifest.json" }
        document::Meta { name: "theme-color", content: "#f5b72b" }
        document::Link { rel: "stylesheet", href: TAILWIND_CSS }
        // Service worker disabled for now — causes stale cache issues on redeploy
        // script { r#"if('serviceWorker' in navigator)navigator.serviceWorker.register('/assets/sw.js')"# }
        // Unregister any existing service worker
        script { r#"if('serviceWorker' in navigator)navigator.serviceWorker.getRegistrations().then(r=>r.forEach(w=>w.unregister()))"# }
        document::Meta { property: "og:type", content: "website" }
        document::Meta { property: "og:image", content: BANNER_IMAGE }
        document::Meta { property: "og:url", content: "https://microvisor.systems" }
        document::Meta { property: "og:title", content: "Apidae Systems" }
        document::Meta { name: "twitter:card", content: "summary_large_image" }
        document::Meta {
            property: "og:description",
            content: "From Bootloader to Browser.",
        }

        div { class: "min-h-screen", Router::<Route> {} }
    }
}

#[server(endpoint = "static_routes", output = server_fn::codec::Json)]
async fn static_routes() -> Result<Vec<String>, ServerFnError> {
    Ok(Route::static_routes()
        .iter()
        .map(ToString::to_string)
        .collect())
}
