use std::collections::HashMap;

use cadrum::{DMat3, DVec3};
use robot_description::{link::LinkId, MM3_TO_M3, MM5_TO_M5, MM_TO_M};

use crate::{
    material::{dominant_material, Material},
    Link,
};

pub struct LinkSummary {
    pub id: LinkId,
    pub parts: usize,
    pub material: Option<Material>,
    pub mass: f64,
    pub center_local: DVec3,
    pub inertia: DMat3,
}

pub fn summarize(link: &Link) -> LinkSummary {
    let mut mass = 0.0;
    let mut weighted_center = DVec3::ZERO;
    let mut inertia_about_world_origin = DMat3::ZERO;
    let mut mass_by_material: HashMap<Material, f64> = HashMap::new();
    for solid in &link.solids {
        let Some(material) = dominant_material(solid) else {
            continue;
        };
        let density = material.density_kg_per_m3();
        let solid_mass = solid.volume().abs() * MM3_TO_M3 * density;
        mass += solid_mass;
        weighted_center += solid_mass * (solid.center() * MM_TO_M);
        inertia_about_world_origin += solid.inertia() * (density * MM5_TO_M5);
        *mass_by_material.entry(material).or_insert(0.0) += solid_mass;
    }

    let material = mass_by_material
        .into_iter()
        .max_by(|left, right| left.1.total_cmp(&right.1))
        .map(|(material, _)| material);

    let (center_local, inertia) = if mass > 0.0 {
        let center = weighted_center / mass;
        let parallel_axis_shift = center.length_squared() * DMat3::IDENTITY
            - DMat3::from_cols(center * center.x, center * center.y, center * center.z);
        (
            center - link.origin_world * MM_TO_M,
            inertia_about_world_origin - parallel_axis_shift * mass,
        )
    } else {
        (DVec3::ZERO, DMat3::ZERO)
    };

    LinkSummary {
        id: link.id,
        parts: link.solids.len(),
        material,
        mass,
        center_local,
        inertia,
    }
}
