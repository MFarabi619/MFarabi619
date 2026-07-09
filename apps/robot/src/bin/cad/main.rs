use std::{
    error::Error,
    f64::consts::{FRAC_PI_2, PI},
    fs::{self, File},
    path::{Path, PathBuf},
};

use cadrum::{DVec3, Solid};

mod parameters;
use parameters::{
    ALUMINUM_COLOR, CASTER_RADIUS, CASTER_WIDTH, DRIVE_WHEEL_TRACK, FRAME_LENGTH, FRAME_TOP_Z,
    FRAME_WIDTH, PLANK_LENGTH, PLANK_THICKNESS, PLANK_WIDTH, PLYWOOD_COLOR, RAIL_PROFILE,
    RUBBER_COLOR, WHEELBASE, WHEEL_RADIUS,
};

const DRIVE_WHEEL_ASSET: &str = "motor_with_bracket_and_wheel.step";

fn asset(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("assets").join(name)
}

fn box_centered(size: DVec3, center: DVec3) -> Solid {
    Solid::cube(center - size / 2.0, center + size / 2.0)
}

fn plank() -> Solid {
    box_centered(
        DVec3::new(PLANK_LENGTH, PLANK_WIDTH, PLANK_THICKNESS),
        DVec3::new(WHEELBASE / 2.0, 0.0, FRAME_TOP_Z + PLANK_THICKNESS / 2.0),
    )
    .color(PLYWOOD_COLOR)
}

fn frame() -> Vec<Solid> {
    let rail_center_z = FRAME_TOP_Z - RAIL_PROFILE / 2.0;
    let side_y = FRAME_WIDTH / 2.0 - RAIL_PROFILE / 2.0;
    let front_x = WHEELBASE / 2.0 + FRAME_LENGTH / 2.0 - RAIL_PROFILE / 2.0;
    let rear_x = WHEELBASE / 2.0 - FRAME_LENGTH / 2.0 + RAIL_PROFILE / 2.0;
    let cross_length = FRAME_WIDTH - 2.0 * RAIL_PROFILE;

    [
        box_centered(
            DVec3::new(FRAME_LENGTH, RAIL_PROFILE, RAIL_PROFILE),
            DVec3::new(WHEELBASE / 2.0, side_y, rail_center_z),
        ),
        box_centered(
            DVec3::new(FRAME_LENGTH, RAIL_PROFILE, RAIL_PROFILE),
            DVec3::new(WHEELBASE / 2.0, -side_y, rail_center_z),
        ),
        box_centered(
            DVec3::new(RAIL_PROFILE, cross_length, RAIL_PROFILE),
            DVec3::new(front_x, 0.0, rail_center_z),
        ),
        box_centered(
            DVec3::new(RAIL_PROFILE, cross_length, RAIL_PROFILE),
            DVec3::new(rear_x, 0.0, rail_center_z),
        ),
    ]
    .into_iter()
    .map(|rail| rail.color(ALUMINUM_COLOR))
    .collect()
}

fn caster() -> Solid {
    let width_axis = DVec3::Y * CASTER_WIDTH;
    Solid::cylinder(CASTER_RADIUS, width_axis)
        .translate(DVec3::new(WHEELBASE, 0.0, CASTER_RADIUS) - width_axis / 2.0)
        .color(RUBBER_COLOR)
}

fn combined_bounds(solids: &[Solid]) -> [DVec3; 2] {
    let mut min = DVec3::splat(f64::INFINITY);
    let mut max = DVec3::splat(f64::NEG_INFINITY);
    for solid in solids {
        let [low, high] = solid.bounding_box();
        min = min.min(low);
        max = max.max(high);
    }
    [min, max]
}

fn bounding_center(solids: &[Solid]) -> DVec3 {
    let [min, max] = combined_bounds(solids);
    (min + max) / 2.0
}

fn plank_top_z() -> f64 {
    FRAME_TOP_Z + PLANK_THICKNESS
}

fn part_on_plank(
    asset_name: &str,
    position: DVec3,
    orient: impl Fn(Solid) -> Solid,
) -> Result<Vec<Solid>, Box<dyn Error>> {
    let raw = Solid::read_step(&mut File::open(asset(asset_name))?)?;
    let oriented: Vec<Solid> = raw.into_iter().map(orient).collect();
    let [min, max] = combined_bounds(&oriented);
    let footprint = DVec3::new((min.x + max.x) / 2.0, (min.y + max.y) / 2.0, min.z);
    Ok(oriented
        .into_iter()
        .map(|solid| solid.translate(-footprint).translate(position))
        .collect())
}

fn deck_parts() -> Result<Vec<Solid>, Box<dyn Error>> {
    let top = plank_top_z();
    let mut parts = Vec::new();
    parts.extend(part_on_plank(
        "18ah-battery.step",
        DVec3::new(110.0, 0.0, top),
        |solid| solid.rotate_x(FRAC_PI_2),
    )?);
    // parts.extend(part_on_plank("rpi5.step", DVec3::new(250.0, 110.0, top), |solid| solid)?);
    // parts.extend(part_on_plank("nucleo_h755zi_q.step", DVec3::new(250.0, -110.0, top), |solid| solid)?);
    parts.extend(part_on_plank(
        "cytron-hat-md30c.STEP",
        DVec3::new(110.0, 110.0, top),
        |solid| solid.rotate_z(PI),
    )?);
    parts.extend(part_on_plank(
        "cytron-hat-md30c.STEP",
        DVec3::new(110.0, -110.0, top),
        |solid| solid,
    )?);
    Ok(parts)
}

fn drive_wheels() -> Result<Vec<Solid>, Box<dyn Error>> {
    let raw = Solid::read_step(&mut File::open(asset(DRIVE_WHEEL_ASSET))?)?;
    let center = bounding_center(&raw);

    let mut wheels = Vec::with_capacity(raw.len() * 2);
    for solid in &raw {
        wheels.push(
            solid
                .clone()
                .translate(-center)
                .translate(DVec3::new(0.0, -DRIVE_WHEEL_TRACK / 2.0, WHEEL_RADIUS)),
        );
        wheels.push(
            solid
                .clone()
                .translate(-center)
                .mirror(DVec3::ZERO, DVec3::Y)
                .translate(DVec3::new(0.0, DRIVE_WHEEL_TRACK / 2.0, WHEEL_RADIUS)),
        );
    }
    Ok(wheels)
}

fn robot() -> Result<Vec<Solid>, Box<dyn Error>> {
    let mut parts = vec![plank(), caster()];
    parts.extend(frame());
    parts.extend(drive_wheels()?);
    parts.extend(deck_parts()?);
    Ok(parts)
}

fn main() -> Result<(), Box<dyn Error>> {
    let output_directory = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets");
    fs::create_dir_all(&output_directory)?;

    let solids = robot()?;
    let mesh = Solid::mesh(&solids, Default::default())?;

    let step_path = output_directory.join("robot.step");
    let glb_path = output_directory.join("robot.glb");
    let stl_path = output_directory.join("robot.stl");
    let png_path = output_directory.join("robot.png");

    Solid::write_step(&solids, &mut File::create(&step_path)?)?;
    mesh.write_stl(&mut File::create(&stl_path)?)?;
    mesh.write_multiview_png(&mut File::create(&png_path)?)?;

    let gltf_solids: Vec<Solid> =
        solids.iter().cloned().map(|solid| solid.align_z(DVec3::Y, DVec3::X)).collect();
    let gltf_mesh = Solid::mesh(&gltf_solids, Default::default())?;
    gltf_mesh.write_gltf_binary(&mut File::create(&glb_path)?)?;

    for path in [&step_path, &glb_path, &stl_path, &png_path] {
        println!("wrote {}", path.display());
    }
    Ok(())
}
