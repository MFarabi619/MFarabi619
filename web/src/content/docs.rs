use dioxus::prelude::*;
use lucide_dioxus::{Check, Copy};
use ui::components::button::{Button, ButtonSize, ButtonVariant};
use wasm_bindgen::JsCast;

// This module does not exist in the git repo - it is auto-generated at build time.
pub mod router;

#[component]
fn SandBoxFrame(url: String) -> Element {
    rsx! {
        iframe {
            class: "border rounded-md border-border shadow-sm",
            width: "800",
            height: "450",
            src: "{url}?embed=1",
            "allowfullscreen": true,
        }
    }
}

#[component]
fn DemoFrame(children: Element) -> Element {
    rsx! {
        div {
            class: "bg-background border border-border rounded-lg shadow p-6 my-6 overflow-visible text-foreground",
            {children}
        }
    }
}

#[component]
fn CodeBlock(contents: String, name: Option<String>) -> Element {
    let mut copied = use_signal(|| false);
    let code_id = use_hook(|| format!("code-{:x}", {
        let mut hash: u64 = 5381;
        for byte in contents.bytes() { hash = hash.wrapping_mul(33).wrapping_add(byte as u64); }
        hash
    }));
    let code_id_for_click = code_id.clone();

    rsx! {
        div {
            class: "rounded-lg border border-border shadow-sm mb-6 overflow-hidden",
            div {
                class: "bg-card flex justify-between items-center p-2 text-xs font-mono rounded-t-lg",
                div {
                    class: "text-card-foreground",
                    if let Some(path) = name {
                        "src/{path}"
                    }
                }
                Button {
                    variant: ButtonVariant::Ghost,
                    size: ButtonSize::Small,
                    on_click: move |_| {
                        let id = code_id_for_click.clone();
                        if let Some(el) = web_sys::window()
                            .and_then(|w| w.document())
                            .and_then(|d| d.get_element_by_id(&id))
                            .and_then(|el| el.dyn_into::<web_sys::HtmlElement>().ok())
                        {
                            let text = el.inner_text();
                            if let Some(window) = web_sys::window() {
                                let _ = window.navigator().clipboard().write_text(&text);
                                copied.set(true);
                            }
                        }
                    },
                    if copied() {
                        div { class: "flex gap-1 text-green-500 items-center",
                            Check { class: "w-4 h-4" }
                            "Copied!"
                        }
                    }
                    else {
                        Copy { class: "w-4 h-4" }
                    }
                }
            }
            div { id: "{code_id}", class: "codeblock text-xs bg-[#0d0d0d] p-4 overflow-auto", dangerous_inner_html: contents }
        }
    }
}
