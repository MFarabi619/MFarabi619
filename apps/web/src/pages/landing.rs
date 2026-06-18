use crate::brand;
use dioxus::prelude::*;
use ui::components::button::{Button, ButtonVariant};

#[component]
pub fn Landing() -> Element {
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
                    class: "transition-transform duration-300 ease-in-out \
                            h-auto mx-auto mb-6 w-[min(180px,35vmin)] \
                            group-hover:scale-105",
                    style: "filter: var(--hero-glow);",
                    src: brand::ACTIVE.logo,
                    alt: "{brand::ACTIVE.name} logo",
                }
                h1 {
                    class: "font-extrabold text-[clamp(28px,4.5vmin,56px)] m-[0.5rem_0_0.25rem]",
                    "{brand::ACTIVE.hero_emoji_accent}"
                    span {
                        style: "background: var(--hero-gradient); \
                                -webkit-background-clip: text; \
                                background-clip: text; \
                                color: transparent;",
                        " {brand::ACTIVE.name} "
                    }
                    "{brand::ACTIVE.hero_emoji_accent}"
                }
                p {
                    class: "mt-3 text-[1.1rem] text-gray-200",
                    "{brand::ACTIVE.tagline}"
                }
            }
        }

        section { class: "mx-auto min-h-[50vh] w-full max-w-3xl px-6",
            div { class: "bg-[rgba(255,255,255,0.06)] border border-[rgba(255,255,255,0.1)] backdrop-blur-[16px] shadow-[0_20px_60px_rgba(0,0,0,0.5)] rounded-[18px] px-6 sm:px-10 py-8",

                div { class: "flex justify-center mb-4",
                    span { class: "inline-flex items-center gap-2 px-3 py-1 rounded-full border border-[rgba(255,255,255,0.12)] bg-[rgba(0,0,0,0.25)] text-xs tracking-wide text-gray-200/90",
                        span { class: "relative flex",
                            span { class: "absolute inline-flex w-2.5 h-2.5 rounded-full bg-emerald-400 shadow-[0_0_14px_rgba(16,185,129,0.8)] animate-ping" }
                            span { class: "relative w-2.5 h-2.5 rounded-full bg-emerald-400 shadow-[0_0_14px_rgba(16,185,129,0.8)]" }
                        }
                        "Served from ESP32S3"
                        span { class: "opacity-70", "•" }
                        span { class: "opacity-80", "10.0.0.236 • RSSI -19 dBm • up 5d 23h 16m 21s" }
                    }
                }

                div { class: "flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3",
                    div { class: "mt-6 flex gap-3",
                        a {
                            href: "/health", target: "_blank",
                            class: "inline-flex items-center gap-2 rounded-full px-4 py-2 text-sm",
                            span { class: "inline-block w-2 h-2 rounded-full bg-emerald-400" }
                            "/health"
                        }
                        a {
                            href: "/ready", target: "_blank",
                            class: "inline-flex items-center gap-2 rounded-full px-4 py-2 text-sm",
                            span { class: "inline-block w-2 h-2 rounded-full bg-sky-400" }
                            "/ready"
                        }
                        a {
                            href: "/api/status", target: "_blank",
                            class: "inline-flex items-center gap-2 rounded-full px-4 py-2 text-sm",
                            span { class: "inline-block w-2 h-2 rounded-full bg-fuchsia-400" }
                            "/api/status"
                        }
                    }
                    div { class: "flex items-center gap-2",
                        Button {
                            class: "inline-flex items-center justify-center rounded-full px-4 py-2 text-sm border border-[rgba(255,255,255,0.14)] bg-[rgba(0,0,0,0.25)] hover:bg-[rgba(255,255,255,0.08)] transition".to_string(),
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

        section { class: "w-full mb-40 mt-20",
            likec4-view {
                "browser": "true",
                "dynamic-variant": "diagram",
                "view-id": "index",
            }
        }

        section { class: "w-full",
            iframe {
                allowfullscreen: "true",
                class: "min-h-screen w-full",
                src: "https://openws.org",
                title: "OpenWS Homepage",
            }
        }
    }
}
