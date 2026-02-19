use dioxus::document;
use dioxus::prelude::*;

mod components;
mod content;
mod layouts;
mod pages;

use crate::content::docs;
use crate::layouts::{DocsLayout, MainLayout};
use crate::pages::{Err404, Home};

const BANNER_IMAGE: Asset = asset!("/assets/header.svg");
const TAILWIND_CSS: Asset = asset!("/assets/tailwind.css");
const FAVICON: Asset = asset!("/assets/nix-mfarabi.svg");
const MICROVISOR_SYSTEMS_SYMBOL_SMALL: Asset = asset!("/assets/nix-mfarabi.svg");

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
        document::Link { rel: "stylesheet", href: TAILWIND_CSS }
        document::Meta { property: "og:type", content: "website" }
        document::Meta { property: "og:image", content: BANNER_IMAGE }
        document::Meta { property: "og:url", content: "https://microvisor.systems" }
        document::Meta { property: "og:title", content: "🕹 Microvisor Systems 🕹" }
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
