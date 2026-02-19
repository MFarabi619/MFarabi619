use crate::Route;
use dioxus::prelude::*;
use lucide_dioxus::House;
use ui::components::button::{Button, ButtonSize, ButtonVariant};

#[component]
pub fn Err404(segments: Vec<String>) -> Element {
    let _ = segments;
    rsx! {
        div { class: "min-h-screen flex items-center justify-center bg-background",
            div { class: "text-center px-6 py-12 max-w-md mx-auto",
                h1 { class: "text-9xl font-extrabold text-primary mb-2", "404" }
                h2 { class: "text-3xl font-bold text-foreground mb-4", "Page Not Found" }
                p { class: "text-lg text-muted-foreground mb-8",
                    "Sorry, we couldn't find the page you're looking for."
                }

                div { class: "flex justify-center",
                    Link { to: Route::Home {},
                        Button {
                            variant: ButtonVariant::Primary,
                            size: ButtonSize::Large,
                            icon_left: rsx! { House { class: "w-5 h-5 mr-2" } },
                            "Back to Home"
                        }
                    }
                }
            }
        }
    }
}
