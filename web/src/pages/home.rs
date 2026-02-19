use crate::MICROVISOR_SYSTEMS_SYMBOL_SMALL;
use dioxus::prelude::*;
use ui::components::button::{Button, ButtonVariant};

#[component]
pub fn Home() -> Element {
    rsx! {
        main {
            class: "flex w-full justify-center items-center min-h-screen px-6 py-32",
            section {
              class: "group w-fit \
                        bg-[rgba(255,255,255,0.06)] \
                        border border-[rgba(255,255,255,0.1)] \
                        backdrop-blur-[16px] \
                        shadow-[0_20px_60px_rgba(0,0,0,0.5)] \
                        rounded-[18px] \
                        px-16 py-6 text-center",

                img {
                    class: "drop-shadow-[0_0_20px_rgba(204,0,255,0.4)] \
                            drop-shadow-[0_0_12px_rgba(255,238,0,0.3)] \
                            transition-transform duration-300 ease-in-out \
                            h-auto mx-auto mb-6 w-[min(180px,35vmin)] \
                            group-hover:scale-105",
                  src: MICROVISOR_SYSTEMS_SYMBOL_SMALL,
                    alt: "Microvisor Systems logo",
                }

                h1 {
                  class: "font-extrabold text-[clamp(28px,4.5vmin,56px)] m-[0.5rem_0_0.25rem]",
    "🕹"
                    span {
                        class: "bg-[linear-gradient(90deg,#ffd200_0%,#ec8c78_33%,#e779c1_67%,#58c7f3_100%)] bg-clip-text text-transparent",
                        " Microvisor Systems "
                    }
                  "🕹"
                }

                p {
                    class: "mt-3 text-[1.1rem] text-gray-200",
                    "🤖 Beep boop, from bootloader to browser 🤖"
                }
            }
        }

            section {
                class: "mx-auto min-h-[50vh] w-full max-w-3xl",
            div {
                class: "bg-[rgba(255,255,255,0.06)] border border-[rgba(255,255,255,0.1)] backdrop-blur-[16px] shadow-[0_20px_60px_rgba(0,0,0,0.5)] rounded-[18px] px-6 sm:px-10 py-8",

                div { class: "flex justify-center mb-4",
                    span { class: "inline-flex items-center gap-2 px-3 py-1 rounded-full border border-[rgba(255,255,255,0.12)] bg-[rgba(0,0,0,0.25)] text-xs tracking-wide text-gray-200/90",
                        span { class: "relative flex",
                            span { class: "absolute inline-flex w-2.5 h-2.5 rounded-full bg-emerald-400 shadow-[0_0_14px_rgba(16,185,129,0.8)] animate-ping" }
                            span { class: "relative w-2.5 h-2.5 rounded-full bg-emerald-400 shadow-[0_0_14px_rgba(16,185,129,0.8)]" }
                        }
                        "Served from ESP32S3"
                        span { class: "opacity-70", "•" }
                        span { class: "opacity-80",
                            "10.0.0.236 • RSSI -19 dBm • up 5d 23h 16m 21s"
                        }
                    }
                }

                div { class: "flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3",
                    div { class: "mt-6 flex gap-3",

                        a {
                            href: "/health",
                            target: "_blank",
                            class: "inline-flex items-center gap-2 rounded-full px-4 py-2 text-sm",
                            span { class: "inline-block w-2 h-2 rounded-full bg-emerald-400" }
                            "/health"
                        }

                        a {
                            href: "/ready",
                            target: "_blank",
                            class: "inline-flex items-center gap-2 rounded-full px-4 py-2 text-sm",
                            span { class: "inline-block w-2 h-2 rounded-full bg-sky-400" }
                            "/ready"
                        }

                        a {
                            href: "/api/status",
                            target: "_blank",
                            class: "inline-flex items-center gap-2 rounded-full px-4 py-2 text-sm",
                            span { class: "inline-block w-2 h-2 rounded-full bg-fuchsia-400" }
                            "/api/status"
                        }
                    }

                    div { class: "flex items-center gap-2",
                        Button {
                            class: "inline-flex items-center justify-center rounded-full px-4 py-2 text-sm border border-[rgba(255,255,255,0.14)] bg-[rgba(0,0,0,0.25)] hover:bg-[rgba(255,255,255,0.08)] transition",
                            variant: ButtonVariant::Outline,
                            on_click: |_| {},
                            "Refresh"
                        }

                        span { class: "inline-flex items-center gap-2 px-3 py-2 rounded-full text-xs border border-[rgba(255,255,255,0.12)] bg-[rgba(0,0,0,0.25)] opacity-90",
                            span { class: "inline-block w-2 h-2 rounded-full bg-emerald-400" }
                            span { "Live" }
                        }
                    }
                }

                div { class: "mt-6 grid grid-cols-1 sm:grid-cols-2 gap-4",
                    div { class: "rounded-xl border border-[rgba(255,255,255,0.1)] bg-[rgba(0,0,0,0.22)] p-4",
                        div { class: "text-xs uppercase tracking-wider opacity-70", "IP" }
                        div { class: "mt-1 text-lg font-semibold", "10.0.0.236" }
                    }

                    div { class: "rounded-xl border border-[rgba(255,255,255,0.1)] bg-[rgba(0,0,0,0.22)] p-4",
                        div { class: "text-xs uppercase tracking-wider opacity-70", "RSSI" }
                        div { class: "mt-1 text-lg font-semibold", "-19 dBm" }
                    }

                    div { class: "rounded-xl border border-[rgba(255,255,255,0.1)] bg-[rgba(0,0,0,0.22)] p-4",
                        div { class: "text-xs uppercase tracking-wider opacity-70", "Uptime" }
                        div { class: "mt-1 text-lg font-semibold", "5d 23h 16m 21s" }
                    }

                    div { class: "rounded-xl border border-[rgba(255,255,255,0.1)] bg-[rgba(0,0,0,0.22)] p-4",
                        div { class: "text-xs uppercase tracking-wider opacity-70", "Free heap" }
                        div { class: "mt-1 text-lg font-semibold", "244,680 bytes" }
                    }
                }
            }
            }
      section {
        class: "w-full mb-40",
                likec4-view {
                    "browser": "true",
                    "dynamic-variant": "diagram",
                    "view-id": "index",
                }
      }
      section {
        class: "w-full",
                    iframe {
                        allowfullscreen: "true",
                        class: "min-h-screen w-full",
                        src: "https://openws.org",
                        title: "OpenWS Homepage",
                    }
      }
    }
}
