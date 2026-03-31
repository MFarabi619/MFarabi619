use crate::Route;
use crate::components::navbar::Navbar;
use dioxus::prelude::*;
use dioxus_router::{Outlet, use_route};
use ui::components::side_sheet::SideSheet;

#[component]
pub fn MainLayout() -> Element {
    let route = use_route::<Route>();
    let title = match route {
        Route::Home { .. } => "🕹 Microvisor Systems 🕹",
        Route::Docs { .. } => "🕹 Microvisor Systems 🕹 - Docs",
        Route::Err404 { .. } => "🕹 Microvisor Systems 🕹 - Page Not Found",
    };

    rsx! {
        document::Title { "{title}" }
        SideSheet {
            div { class: "min-h-screen overflow-x-hidden bg-zinc-950 text-gray-200 font-sans relative",
                div { class: "fixed inset-0 blur-[120px] saturate-[140%] opacity-60 pointer-events-none z-0", aria_hidden: "true",
                    div { class: "absolute w-[60vmax] h-[60vmax] rounded-full opacity-60 mix-blend-screen will-change-[transform,opacity] animate-[float_25s_ease-in-out_infinite_alternate] [animation-delay:-6s] bg-[radial-gradient(circle,#cc00ff,transparent_70%)] top-[-20%] left-[-15%]" }
                    div { class: "absolute w-[60vmax] h-[60vmax] rounded-full opacity-60 mix-blend-screen will-change-[transform,opacity] animate-[float_25s_ease-in-out_infinite_alternate] [animation-delay:-12s] bg-[radial-gradient(circle,#ffee00,transparent_70%)] top-[-8%] left-[75%]" }
                    div { class: "absolute w-[60vmax] h-[60vmax] rounded-full opacity-60 mix-blend-screen will-change-[transform,opacity] animate-[float_25s_ease-in-out_infinite_alternate] [animation-delay:-18s] bg-[radial-gradient(circle,#00ff22,transparent_70%)] top-[75%] left-[40%]" }
                }

                div { class: "relative z-10",
                    Navbar {}
                    div { class: "flex flex-col justify-center items-center max-w-6xl container mx-auto",
                        Outlet::<Route> {}
                    }
                  footer {
                    class: "mt-20 py-6 text-center text-muted dark:text-gray-400",
                    p {
                      class: "w-fit mx-auto bg-[linear-gradient(90deg,#ffd200_0%,#ec8c78_33%,#e779c1_67%,#58c7f3_100%)] bg-clip-text text-transparent",
                        "© 2026 Microvisor Systems." }
                      span { "Made by " }
                    a {
                        target: "_blank",
                        rel: "noopener noreferrer",
                      class: "text-rose-400 hover:text-primary hover:underline transition-colors",
                        href: "https://github.com/mfarabi619",
                      "Mumtahin Farabi"
                    }
                      " with "
                    a {
                        target: "_blank",
                        rel: "noopener noreferrer",
                        href: "https://nixos.org",
                      img {
                        class: "inline w-5",
                        src: "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/nix.svg"
                      }
                    }
                      ", "
                    a {
                        target: "_blank",
                        rel: "noopener noreferrer",
                        href: "https://rust-lang.org",
                      img {
                        class: "inline w-5",
                        src: "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/rust-symbol.svg"
                      }
                    }
                      ","
                    a {
                        target: "_blank",
                        rel: "noopener noreferrer",
                        href: "https://dioxuslabs.com",
                      img {
                        class: "inline w-6",
                        src: "https://raw.githubusercontent.com/DioxusLabs/brand/4f5601935824dd39962f8982feda06c95eae026a/logos/multiplatform.svg"
                      }
                    },
                      ", & "
                    a {
                        target: "_blank",
                        rel: "noopener noreferrer",
                        href: "https://lumenblocks.dev",
                      img {
                        class: "inline w-5",
                        src: "https://lumenblocks.dev/assets/lumen-logo-small-dxh104608121b07667.png"
                      }
                    }
                    }
                }
            }
        }
    }
}
