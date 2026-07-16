use std::collections::HashMap;

use cadrum::{Color, Solid};

const ALUMINUM_DENSITY_KG_PER_M3: f64 = 2700.0;
const STEEL_DENSITY_KG_PER_M3: f64 = 7850.0;
const PLYWOOD_DENSITY_KG_PER_M3: f64 = 600.0;
const RUBBER_DENSITY_KG_PER_M3: f64 = 1200.0;
const PLASTIC_DENSITY_KG_PER_M3: f64 = 1140.0;
const SLA_BATTERY_DENSITY_KG_PER_M3: f64 = 2400.0;

const PLYWOOD_COLOR: [u8; 3] = [0xc8, 0xa0, 0x6e];
const ALUMINUM_COLOR: [u8; 3] = [0xb0, 0xb3, 0xb8];
const STEEL_COLOR: [u8; 3] = [0x5a, 0x5d, 0x63];
const PLASTIC_COLOR: [u8; 3] = [0x10, 0x10, 0x10];
const RUBBER_COLOR: [u8; 3] = [0x0c, 0x0c, 0x0c];
const SLA_BATTERY_COLOR: [u8; 3] = [0x14, 0x14, 0x14];
const ANODIZED_ALUMINUM_COLOR: [u8; 3] = [0x9d, 0xcf, 0xed];

pub struct Pbr {
    pub metallic: f32,
    pub roughness: f32,
}

pub const DEFAULT_MATERIAL_RGB: [u8; 3] = [0xdd, 0xdd, 0xdd];

pub const UNKNOWN_MATERIAL_PBR: Pbr = Pbr {
    metallic: 0.3,
    roughness: 0.7,
};

#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub enum Material {
    Aluminum,
    AnodizedAluminum,
    Steel,
    Plastic,
    Plywood,
    Rubber,
    SlaBattery,
}

impl Material {
    pub const ALL: [Material; 7] = [
        Material::Aluminum,
        Material::AnodizedAluminum,
        Material::Steel,
        Material::Plastic,
        Material::Plywood,
        Material::Rubber,
        Material::SlaBattery,
    ];

    pub const fn label(self) -> &'static str {
        match self {
            Material::Aluminum => "aluminum",
            Material::AnodizedAluminum => "anodized_aluminum",
            Material::Steel => "steel",
            Material::Plastic => "plastic",
            Material::Plywood => "plywood",
            Material::Rubber => "rubber",
            Material::SlaBattery => "sla_battery",
        }
    }

    pub const fn density_kg_per_m3(self) -> f64 {
        match self {
            Material::Aluminum | Material::AnodizedAluminum => ALUMINUM_DENSITY_KG_PER_M3,
            Material::Steel => STEEL_DENSITY_KG_PER_M3,
            Material::Plastic => PLASTIC_DENSITY_KG_PER_M3,
            Material::Plywood => PLYWOOD_DENSITY_KG_PER_M3,
            Material::Rubber => RUBBER_DENSITY_KG_PER_M3,
            Material::SlaBattery => SLA_BATTERY_DENSITY_KG_PER_M3,
        }
    }

    pub const fn pbr(self) -> Pbr {
        match self {
            Material::Aluminum => Pbr {
                metallic: 0.6,
                roughness: 0.55,
            },
            Material::AnodizedAluminum => Pbr {
                metallic: 0.9,
                roughness: 0.2,
            },
            Material::Steel => Pbr {
                metallic: 0.35,
                roughness: 0.75,
            },
            Material::Plastic => Pbr {
                metallic: 0.0,
                roughness: 0.6,
            },
            Material::Plywood => Pbr {
                metallic: 0.0,
                roughness: 0.9,
            },
            Material::Rubber => Pbr {
                metallic: 0.0,
                roughness: 0.95,
            },
            Material::SlaBattery => Pbr {
                metallic: 0.0,
                roughness: 0.9,
            },
        }
    }

    pub const fn rgb(self) -> [u8; 3] {
        match self {
            Material::Aluminum => ALUMINUM_COLOR,
            Material::AnodizedAluminum => ANODIZED_ALUMINUM_COLOR,
            Material::Steel => STEEL_COLOR,
            Material::Plastic => PLASTIC_COLOR,
            Material::Plywood => PLYWOOD_COLOR,
            Material::Rubber => RUBBER_COLOR,
            Material::SlaBattery => SLA_BATTERY_COLOR,
        }
    }

    pub fn from_rgb(rgb: [u8; 3]) -> Option<Material> {
        Material::ALL.into_iter().find(|m| m.rgb() == rgb)
    }

    pub fn pbr_for_rgb(rgb: [u8; 3]) -> Pbr {
        Material::from_rgb(rgb).map_or(UNKNOWN_MATERIAL_PBR, Material::pbr)
    }
}

pub trait WithMaterial {
    fn with_material(self, material: Material) -> Self;
}

impl WithMaterial for Solid {
    fn with_material(self, material: Material) -> Self {
        let [r, g, b] = material.rgb();
        self.color(Color {
            r: r as f32 / 255.0,
            g: g as f32 / 255.0,
            b: b as f32 / 255.0,
        })
    }
}

pub fn quantize(color: Color) -> [u8; 3] {
    [
        (color.r.clamp(0.0, 1.0) * 255.0) as u8,
        (color.g.clamp(0.0, 1.0) * 255.0) as u8,
        (color.b.clamp(0.0, 1.0) * 255.0) as u8,
    ]
}

pub fn dominant_rgb(solid: &Solid) -> Option<[u8; 3]> {
    let mut counts: HashMap<[u8; 3], usize> = HashMap::new();
    for color in solid.colormap().values() {
        *counts.entry(quantize(*color)).or_insert(0) += 1;
    }
    counts
        .into_iter()
        .max_by_key(|(_, count)| *count)
        .map(|(rgb, _)| rgb)
}

pub fn dominant_material(solid: &Solid) -> Option<Material> {
    dominant_rgb(solid).and_then(Material::from_rgb)
}
