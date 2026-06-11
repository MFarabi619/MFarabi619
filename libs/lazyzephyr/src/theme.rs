use ratatui::style::{
    Color,
    palette::tailwind::{AMBER, EMERALD, LIME, ORANGE, ROSE, SLATE},
};

#[derive(Clone, Copy)]
pub struct Theme {
    pub name:                 &'static str,
    pub border:               Color,
    pub accent:               Color,
    pub foreground:           Color,
    pub label:                Color,
    pub value:                Color,
    pub success:              Color,
    pub warning:              Color,
    pub error:                Color,
    pub tiers:                [Color; 5],
    pub selection_background: Color,
    pub selection_foreground: Color,
}

impl Theme {
    pub fn tier_for_ratio(&self, ratio: f64) -> Color {
        let clamped = ratio.clamp(0.0, 0.9999);
        let bucket = (clamped * 5.0) as usize;
        self.tiers[bucket.min(4)]
    }
}

const TAILWIND: Theme = Theme {
    name: "tailwind",
    border:               SLATE.c700,
    accent:               EMERALD.c400,
    foreground:           SLATE.c200,
    label:                SLATE.c500,
    value:                SLATE.c100,
    success:              EMERALD.c400,
    warning:              AMBER.c400,
    error:                ROSE.c400,
    tiers: [LIME.c300, EMERALD.c400, AMBER.c400, ORANGE.c400, ROSE.c500],
    selection_background: SLATE.c800,
    selection_foreground: SLATE.c50,
};

const GRUVBOX: Theme = Theme {
    name: "gruvbox",
    border:               Color::Rgb(0x92, 0x83, 0x74),
    accent:               Color::Rgb(0x8e, 0xc0, 0x7c),
    foreground:           Color::Rgb(0xeb, 0xdb, 0xb2),
    label:                Color::Rgb(0x92, 0x83, 0x74),
    value:                Color::Rgb(0xeb, 0xdb, 0xb2),
    success:              Color::Rgb(0xb8, 0xbb, 0x26),
    warning:              Color::Rgb(0xfa, 0xbd, 0x2f),
    error:                Color::Rgb(0xfb, 0x49, 0x34),
    tiers: [
        Color::Rgb(0x8e, 0xc0, 0x7c),
        Color::Rgb(0xb8, 0xbb, 0x26),
        Color::Rgb(0xfa, 0xbd, 0x2f),
        Color::Rgb(0xfe, 0x80, 0x19),
        Color::Rgb(0xfb, 0x49, 0x34),
    ],
    selection_background: Color::Rgb(0x50, 0x49, 0x45),
    selection_foreground: Color::Rgb(0xfb, 0xf1, 0xc7),
};

const CATPPUCCIN: Theme = Theme {
    name: "catppuccin",
    border:               Color::Rgb(0x6c, 0x70, 0x86),
    accent:               Color::Rgb(0xa6, 0xe3, 0xa1),
    foreground:           Color::Rgb(0xcd, 0xd6, 0xf4),
    label:                Color::Rgb(0x6c, 0x70, 0x86),
    value:                Color::Rgb(0xcd, 0xd6, 0xf4),
    success:              Color::Rgb(0xa6, 0xe3, 0xa1),
    warning:              Color::Rgb(0xf9, 0xe2, 0xaf),
    error:                Color::Rgb(0xf3, 0x8b, 0xa8),
    tiers: [
        Color::Rgb(0x94, 0xe2, 0xd5),
        Color::Rgb(0xa6, 0xe3, 0xa1),
        Color::Rgb(0xf9, 0xe2, 0xaf),
        Color::Rgb(0xfa, 0xb3, 0x87),
        Color::Rgb(0xf3, 0x8b, 0xa8),
    ],
    selection_background: Color::Rgb(0x45, 0x47, 0x5a),
    selection_foreground: Color::Rgb(0xf5, 0xe0, 0xdc),
};

const TOKYONIGHT: Theme = Theme {
    name: "tokyonight",
    border:               Color::Rgb(0x56, 0x5f, 0x89),
    accent:               Color::Rgb(0x9e, 0xce, 0x6a),
    foreground:           Color::Rgb(0xc0, 0xca, 0xf5),
    label:                Color::Rgb(0x56, 0x5f, 0x89),
    value:                Color::Rgb(0xc0, 0xca, 0xf5),
    success:              Color::Rgb(0x9e, 0xce, 0x6a),
    warning:              Color::Rgb(0xe0, 0xaf, 0x68),
    error:                Color::Rgb(0xf7, 0x76, 0x8e),
    tiers: [
        Color::Rgb(0x73, 0xda, 0xca),
        Color::Rgb(0x9e, 0xce, 0x6a),
        Color::Rgb(0xe0, 0xaf, 0x68),
        Color::Rgb(0xff, 0x9e, 0x64),
        Color::Rgb(0xf7, 0x76, 0x8e),
    ],
    selection_background: Color::Rgb(0x33, 0x3a, 0x5b),
    selection_foreground: Color::Rgb(0xc8, 0xd3, 0xf5),
};

const SOLARIZED: Theme = Theme {
    name: "solarized",
    border:               Color::Rgb(0x58, 0x6e, 0x75),
    accent:               Color::Rgb(0x85, 0x99, 0x00),
    foreground:           Color::Rgb(0x93, 0xa1, 0xa1),
    label:                Color::Rgb(0x58, 0x6e, 0x75),
    value:                Color::Rgb(0xfd, 0xf6, 0xe3),
    success:              Color::Rgb(0x85, 0x99, 0x00),
    warning:              Color::Rgb(0xb5, 0x89, 0x00),
    error:                Color::Rgb(0xdc, 0x32, 0x2f),
    tiers: [
        Color::Rgb(0x2a, 0xa1, 0x98),
        Color::Rgb(0x85, 0x99, 0x00),
        Color::Rgb(0xb5, 0x89, 0x00),
        Color::Rgb(0xcb, 0x4b, 0x16),
        Color::Rgb(0xdc, 0x32, 0x2f),
    ],
    selection_background: Color::Rgb(0x07, 0x36, 0x42),
    selection_foreground: Color::Rgb(0xfd, 0xf6, 0xe3),
};

pub const THEMES: &[Theme] = &[GRUVBOX, TAILWIND, CATPPUCCIN, TOKYONIGHT, SOLARIZED];
