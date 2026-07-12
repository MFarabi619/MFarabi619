use cadrum::Solid;

use crate::parameters::{
    ALUMINUM_COLOR, ALUMINUM_DENSITY_KG_PER_M3, BATTERY_COLOR, END_CAP_COLOR,
    PLASTIC_DENSITY_KG_PER_M3, PLYWOOD_COLOR, PLYWOOD_DENSITY_KG_PER_M3,
    RUBBER_DENSITY_KG_PER_M3, SLA_BATTERY_DENSITY_KG_PER_M3, STEEL_COLOR,
    STEEL_DENSITY_KG_PER_M3, TIRE_COLOR, WHEEL_BRACKET_COLOR,
};

pub struct MaterialProps {
    pub metallic: f32,
    pub roughness: f32,
}

impl Default for MaterialProps {
    fn default() -> Self {
        Self { metallic: 0.5, roughness: 0.5 }
    }
}

pub const DEFAULT_MATERIAL_RGB: [u8; 3] = [0xdd, 0xdd, 0xdd];

#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub enum Material {
    Aluminum,
    WheelBracket,
    Steel,
    Plastic,
    Plywood,
    Rubber,
    SlaBattery,
}

impl Material {
    pub const ALL: [Material; 7] = [
        Material::Aluminum,
        Material::WheelBracket,
        Material::Steel,
        Material::Plastic,
        Material::Plywood,
        Material::Rubber,
        Material::SlaBattery,
    ];

    pub const fn urdf_name(self) -> &'static str {
        match self {
            Material::Aluminum | Material::WheelBracket => "aluminum",
            Material::Steel => "steel",
            Material::Plastic => "plastic",
            Material::Plywood => "plywood",
            Material::Rubber => "rubber",
            Material::SlaBattery => "sla-battery",
        }
    }

    pub const fn density_kg_per_m3(self) -> f64 {
        match self {
            Material::Aluminum | Material::WheelBracket => ALUMINUM_DENSITY_KG_PER_M3,
            Material::Steel => STEEL_DENSITY_KG_PER_M3,
            Material::Plastic => PLASTIC_DENSITY_KG_PER_M3,
            Material::Plywood => PLYWOOD_DENSITY_KG_PER_M3,
            Material::Rubber => RUBBER_DENSITY_KG_PER_M3,
            Material::SlaBattery => SLA_BATTERY_DENSITY_KG_PER_M3,
        }
    }

    pub const fn pbr(self) -> MaterialProps {
        match self {
            Material::Aluminum => MaterialProps { metallic: 0.6, roughness: 0.55 },
            Material::WheelBracket => MaterialProps { metallic: 0.25, roughness: 0.65 },
            Material::Steel => MaterialProps { metallic: 0.35, roughness: 0.75 },
            Material::Plastic => MaterialProps { metallic: 0.0, roughness: 0.6 },
            Material::Plywood => MaterialProps { metallic: 0.0, roughness: 0.9 },
            Material::Rubber => MaterialProps { metallic: 0.0, roughness: 0.95 },
            Material::SlaBattery => MaterialProps { metallic: 0.0, roughness: 0.9 },
        }
    }

    pub const fn rgb(self) -> [u8; 3] {
        match self {
            Material::Aluminum => ALUMINUM_COLOR,
            Material::WheelBracket => WHEEL_BRACKET_COLOR,
            Material::Steel => STEEL_COLOR,
            Material::Plastic => END_CAP_COLOR,
            Material::Plywood => PLYWOOD_COLOR,
            Material::Rubber => TIRE_COLOR,
            Material::SlaBattery => BATTERY_COLOR,
        }
    }

    pub fn from_rgb(rgb: [u8; 3]) -> Option<Material> {
        Material::ALL.into_iter().find(|m| m.rgb() == rgb)
    }
}

pub trait WithMaterial {
    fn with_material(self, material: Material) -> Self;
}

impl WithMaterial for Solid {
    fn with_material(self, material: Material) -> Self {
        let [r, g, b] = material.rgb();
        self.color(format!("#{:02x}{:02x}{:02x}", r, g, b).as_str())
    }
}
