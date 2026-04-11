use dioxus::document;
use dioxus::prelude::*;

pub mod api;
mod components;
mod content;
mod layouts;
mod pages;

pub static SHOW_COMMAND_PALETTE: GlobalSignal<bool> = Signal::global(|| false);
pub static SHOW_NETWORK_SHEET: GlobalSignal<bool> = Signal::global(|| false);

#[derive(Clone, Copy)]
pub struct DeviceContext {
    pub chip_model: Signal<String>,
    pub heap_free: Signal<String>,
}

use crate::content::docs;
use crate::layouts::{DocsLayout, MainLayout};
use crate::pages::{Err404, Home, Shell};

const BANNER_IMAGE: Asset = asset!("/assets/header.svg");
const TAILWIND_CSS: Asset = asset!("/assets/tailwind.css");
const FAVICON: Asset = asset!("/assets/symbol.svg");
const APIDAE_SYMBOL: Asset = asset!("/assets/symbol.svg");

#[derive(Clone, Routable, PartialEq, Eq, Debug)]
enum Route {
    #[route("/shell")]
    Shell {},

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
        document::Link { rel: "stylesheet", href: "https://cdn.jsdelivr.net/npm/@xterm/xterm@5/css/xterm.min.css" }
        script { src: "https://cdn.jsdelivr.net/npm/@xterm/xterm@5/lib/xterm.min.js" }
        script { src: "https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10/lib/addon-fit.min.js" }
        script { src: "https://cdn.jsdelivr.net/npm/@xterm/addon-webgl@0.18/lib/addon-webgl.min.js" }
        script { src: "https://cdn.jsdelivr.net/npm/@xterm/addon-web-links@0.11/lib/addon-web-links.min.js" }
        script { src: "https://cdn.jsdelivr.net/npm/@xterm/addon-attach@0.11/lib/addon-attach.min.js" }
        script { src: "https://cdn.jsdelivr.net/npm/spark-md5@3.0.2/spark-md5.min.js" }
        script { "window.CERATINA_THEME={{background:'#0a0a0c',foreground:'#d4a84b',cursor:'#f5b72b',selectionBackground:'rgba(245,183,43,0.3)',black:'#0a0a0c',red:'#e06c6c',green:'#6cc070',yellow:'#f5b72b',blue:'#6c9ee0',magenta:'#c06cc0',cyan:'#6cc0c0',white:'#d4a84b'}};" }
        script { r#"if('serviceWorker' in navigator)navigator.serviceWorker.register('/assets/sw.js')"# }
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
