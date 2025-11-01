use dioxus::prelude::*;
use ui::{Echo, Hero};

/// The Home page component that will be rendered when the current route is `[Route::Home]`
#[component]
pub fn Home() -> Element {
    rsx! {
        Hero {}
        Echo {}
    }
}
