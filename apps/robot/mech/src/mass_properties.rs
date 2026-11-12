use std::collections::HashMap;

use cadrum::{DMat3, DVec3};
use crate::{link::LinkId, CUBIC_METERS_PER_CUBIC_MILLIMETER, QUINTIC_METERS_PER_QUINTIC_MILLIMETER, METERS_PER_MILLIMETER};

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
        let density = material.density_kilograms_per_cubic_meter();
        let solid_mass = solid.volume().abs() * CUBIC_METERS_PER_CUBIC_MILLIMETER * density;
        mass += solid_mass;
        weighted_center += solid_mass * (solid.center() * METERS_PER_MILLIMETER);
        inertia_about_world_origin += solid.inertia() * (density * QUINTIC_METERS_PER_QUINTIC_MILLIMETER);
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
            center - link.origin_world * METERS_PER_MILLIMETER,
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
