use std::{error::Error, fs::File, path::Path};

#[allow(unused_imports)]
use cadrum::SceneOption;
use cadrum::{DVec3, Solid, Tessellation};
use description::MM3_TO_M3;

use crate::{
    gltf::write_shaded_glb,
    material::{dominant_material, Material},
    time_it, Link,
};

fn to_gltf_y_up(solid: Solid) -> Solid {
    solid.align_z(DVec3::Y, DVec3::X)
}

pub const TESSELLATION: Tessellation = Tessellation {
    deflection_linear: 0.01,
    deflection_angular: 0.05,
    relative_linear: true,
    is_parallel: true,
};

pub fn write_glb(links: &[Link], glb_path: &Path) -> Result<(), Box<dyn Error>> {
    let viewer_solids: Vec<Solid> = time_it!(
        "to_gltf_y_up",
        links
            .iter()
            .flat_map(|link| link.solids.iter().cloned())
            .map(to_gltf_y_up)
            .collect()
    );
    let mesh = time_it!("tessellation", Solid::mesh(&viewer_solids, TESSELLATION))?;
    time_it!(
        "gltf write",
        write_shaded_glb(&mesh, Material::pbr_for_rgb, &mut File::create(glb_path)?)
    )?;
    println!("wrote {}", glb_path.display());

    // PNG render is single-threaded via tiny-skia and takes far longer than tessellation on this
    // model (15+ min single-view at 1024²). Un-comment when a still is genuinely needed.
    // time_it!(
    //     "png write",
    //     mesh.scene(SceneOption { shading: true, hidden_edges: false, ..SceneOption::default() })
    //         .write_png([1024, 1024], &mut File::create(&png_path)?)
    // )?;

    Ok(())
}

pub fn report_drivetrain() {
    use description::{
        datums::WHEEL_TREAD_DIAMETER_MM,
        placement::{ground_z, wheel_origin, Corner},
    };
    let front = wheel_origin(Corner::FrontLeft);
    let rear = wheel_origin(Corner::RearLeft);
    println!(
        "drivetrain: track {:.1} mm, axles x {:.1}/{:.1} mm, tread r {:.2} mm, ground clearance {:.1} mm",
        2.0 * front.y,
        front.x,
        rear.x,
        WHEEL_TREAD_DIAMETER_MM / 2.0,
        ground_z(),
    );
}

pub fn report_geometry_table<'a>(solids: impl IntoIterator<Item = &'a Solid>) {
    println!(
        "{:>3} {:>14} {:>12} {:>10} {:>36} {:>30}",
        "id", "material", "volume mm³", "mass kg", "center xyz mm", "bbox size mm"
    );
    let mut total_mass = 0.0;
    for (index, solid) in solids.into_iter().enumerate() {
        let volume = solid.volume().abs();
        let material = dominant_material(solid);
        let material_name = material.map_or("?", Material::label);
        let mass = material.map_or(0.0, |m| volume * MM3_TO_M3 * m.density_kg_per_m3());
        total_mass += mass;
        let center = solid.center();
        let [bmin, bmax] = solid.bounding_box();
        let size = bmax - bmin;
        println!(
            "{:>3} {:>14} {:>12.3e} {:>10.4} {:>10.1}, {:>10.1}, {:>10.1} {:>8.1} × {:>8.1} × {:>8.1}",
            index, material_name, volume, mass,
            center.x, center.y, center.z, size.x, size.y, size.z,
        );
    }
    println!(
        "total assembly mass: {:.3} kg (excludes uncategorized parts)",
        total_mass
    );
}
