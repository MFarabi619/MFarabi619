use crate::Route;
use dioxus::document;
use dioxus::prelude::*;
use dioxus_router::Outlet;

#[component]
pub fn DocsLayout() -> Element {
    rsx! {
        document::Title { "Apidae Systems - Docs" }

        div { class: "min-h-screen w-full border-b border-border",
            div { class: "mx-auto max-w-5xl px-6 py-20",
                div {
                    class: "
                        text-foreground
                        [&_h1]:mb-3 [&_h1]:text-3xl [&_h1]:font-bold [&_h1]:text-foreground
                        [&_p]:my-3
                    ",
                    Outlet::<Route> {}
                }
            }
        }
    }
}
