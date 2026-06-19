use dioxus::prelude::*;

pub struct Brand {
    pub key: &'static str,
    pub name: &'static str,
    pub tagline: &'static str,
    pub homepage_url: &'static str,
    pub logo: Asset,
    pub nav_links: &'static [NavLink],
    pub hero_emoji_accent: &'static str,
    pub attribution_name: &'static str,
    pub attribution_url: &'static str,
}

pub struct NavLink {
    pub label: &'static str,
    pub href: &'static str,
}

const MICROVISOR_SYSTEMS_LOGO: Asset = asset!("/assets/microvisor-systems.svg");
const APIDAE_SYSTEMS_LOGO: Asset = asset!("/assets/apidae-systems.svg");

pub const MICROVISOR_SYSTEMS: Brand = Brand {
    key: "microvisor_systems",
    name: "Microvisor Systems",
    tagline: "🤖 Beep boop, from bootloader to browser 🤖",
    homepage_url: "https://microvisor.systems",
    logo: MICROVISOR_SYSTEMS_LOGO,
    hero_emoji_accent: "🕹",
    attribution_name: "Mumtahin Farabi",
    attribution_url: "https://github.com/mfarabi619",
    nav_links: &[
        NavLink {
            label: "OpenWS",
            href: "https://openws.org",
        },
        NavLink {
            label: "LinkedIn",
            href: "https://www.linkedin.com/company/microvisor-systems/",
        },
        NavLink {
            label: "GitHub",
            href: "https://github.com/microvisor-systems",
        },
    ],
};

pub const APIDAE_SYSTEMS: Brand = Brand {
    key: "apidae_systems",
    name: "Apidae Systems",
    tagline: "🐝 Silicon to Sky 🐝",
    homepage_url: "https://apidae.systems",
    logo: APIDAE_SYSTEMS_LOGO,
    hero_emoji_accent: "🐝",
    attribution_name: "Mumtahin Farabi",
    attribution_url: "https://github.com/mfarabi619",
    nav_links: &[],
};

// pub const ACTIVE: Brand = MICROVISOR_SYSTEMS;
pub const ACTIVE: Brand = APIDAE_SYSTEMS;
