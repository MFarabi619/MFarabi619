use std::{
    collections::HashMap,
    error::Error,
    f64::consts::{FRAC_PI_2, PI},
    fs::{self, File},
    path::{Path, PathBuf},
};

use cadrum::{Boolean, DVec3, Solid, Tessellation};

mod gltf;
mod parameters;

use gltf::{write_lit_gltf, MaterialProps};
use parameters::{
    ALUMINUM_COLOR, ALUMINUM_DENSITY_KG_PER_M3, BATTERY_ANCHOR_BOLT_DIAMETER,
    BATTERY_ANCHOR_HEAD_DIAMETER, BATTERY_ANCHOR_HEAD_HEIGHT, BATTERY_ANCHOR_NUT_DIAMETER,
    BATTERY_ANCHOR_NUT_HEIGHT, BATTERY_COLOR, BATTERY_STRAP_OVERHANG, BATTERY_STRAP_THICKNESS,
    BATTERY_STRAP_WIDTH, BATTERY_STRAP_X_SPACING, CAVITY_OVERSHOOT_MM,
    CUTTER_OVERSHOOT_MM, DRIVE_WHEEL_TRACK, EDGE_COINCIDENCE_EPSILON_MM, END_CAP_COLOR,
    END_FACE_NORMAL_X_THRESHOLD, FRAME_LENGTH, FRAME_TOP_Z, FRAME_WIDTH, GUSSET_ARM_LENGTH,
    GUSSET_ARM_WIDTH, GUSSET_HOLES_PER_ARM, GUSSET_HOLE_DIAMETER, GUSSET_HOLE_PITCH,
    GUSSET_THICKNESS, PLASTIC_DENSITY_KG_PER_M3, PLYWOOD_COLOR, PLYWOOD_DENSITY_KG_PER_M3,
    RAIL_CROSS_HEIGHT, RAIL_CROSS_WIDTH, RAIL_END_CAP_BOSS_DEPTH, RAIL_END_CAP_BOSS_WALL,
    RAIL_END_CAP_FLANGE_THICKNESS, RAIL_FILLET_RADIUS, RAIL_HOLE_DIAMETER, RAIL_HOLE_SPACING,
    POST_HEIGHT, POST_INSET_FROM_END, RAIL_WALL_THICKNESS, RUBBER_DENSITY_KG_PER_M3,
    SLA_BATTERY_DENSITY_KG_PER_M3, STEEL_COLOR, STEEL_DENSITY_KG_PER_M3, TIRE_COLOR,
    WHEEL_RADIUS,
};

const DRIVE_WHEEL_STEP_FILENAME: &str = "motor_with_bracket_and_wheel.step";
const WHEEL_BRACKET_COLOR: [u8; 3] = [0x9d, 0xcf, 0xed];

fn asset(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("assets").join(name)
}

fn hex_color(rgb: [u8; 3]) -> String {
    format!("#{:02x}{:02x}{:02x}", rgb[0], rgb[1], rgb[2])
}

trait Paint {
    fn paint(self, rgb: [u8; 3]) -> Self;
}

impl Paint for Solid {
    fn paint(self, rgb: [u8; 3]) -> Self {
        self.color(hex_color(rgb).as_str())
    }
}

fn box_centered(size: DVec3, center: DVec3) -> Solid {
    Solid::cube(center - size / 2.0, center + size / 2.0)
}

fn plank() -> Solid {
    let plank_length = FRAME_LENGTH - 2.0 * RAIL_CROSS_WIDTH;
    let plank_width = FRAME_WIDTH - 2.0 * RAIL_CROSS_WIDTH;
    let plank_z_center = FRAME_TOP_Z - RAIL_CROSS_HEIGHT / 2.0;
    box_centered(
        DVec3::new(plank_length, plank_width, RAIL_CROSS_HEIGHT),
        DVec3::new(0.0, 0.0, plank_z_center),
    )
    .paint(PLYWOOD_COLOR)
}

fn perforated_rail(length: f64) -> Result<Solid, cadrum::Error> {
    let half_x = length / 2.0;
    let half_y = RAIL_CROSS_WIDTH / 2.0;
    let half_z = RAIL_CROSS_HEIGHT / 2.0;
    let hole_radius = RAIL_HOLE_DIAMETER / 2.0;

    let outer_block = Solid::cube(
        DVec3::new(-half_x, -half_y, -half_z),
        DVec3::new(half_x, half_y, half_z),
    );
    let longitudinal_corner_edges = outer_block.iter_edge().filter(|edge| {
        [edge.start_point(), edge.end_point()].iter().all(|point| {
            (point.y.abs() - half_y).abs() < EDGE_COINCIDENCE_EPSILON_MM
                && (point.z.abs() - half_z).abs() < EDGE_COINCIDENCE_EPSILON_MM
        })
    });
    let filleted_block = outer_block.fillet_edges(RAIL_FILLET_RADIUS, longitudinal_corner_edges)?;

    let end_faces: Vec<&cadrum::Face> = filleted_block
        .iter_face()
        .filter(|face| {
            let (_, normal) = face.project(DVec3::ZERO);
            normal.x.abs() > END_FACE_NORMAL_X_THRESHOLD
        })
        .collect();
    let outer_shell = filleted_block.shell(-RAIL_WALL_THICKNESS, end_faces)?;

    let hole_count = (length / RAIL_HOLE_SPACING).round() as usize;
    let first_hole_x = -((hole_count as f64 - 1.0) * RAIL_HOLE_SPACING) / 2.0;
    let wide_face_row_y_offset = RAIL_HOLE_SPACING;
    let top_bottom_hole_cutter_axis = DVec3::Z * (RAIL_CROSS_HEIGHT + 2.0 * CUTTER_OVERSHOOT_MM);
    let side_hole_cutter_axis = DVec3::Y * (RAIL_CROSS_WIDTH + 2.0 * CUTTER_OVERSHOOT_MM);

    let mut cutters: Vec<Solid> = Vec::new();
    for hole_index in 0..hole_count {
        let x = first_hole_x + hole_index as f64 * RAIL_HOLE_SPACING;
        for &y_row in &[-wide_face_row_y_offset, wide_face_row_y_offset] {
            cutters.push(
                Solid::cylinder(hole_radius, top_bottom_hole_cutter_axis)
                    .translate(DVec3::new(x, y_row, -half_z - CUTTER_OVERSHOOT_MM)),
            );
        }
        cutters.push(
            Solid::cylinder(hole_radius, side_hole_cutter_axis)
                .translate(DVec3::new(x, -half_y - CUTTER_OVERSHOOT_MM, 0.0)),
        );
    }

    cutters
        .iter()
        .map(Boolean::from)
        .fold(Boolean::from(&outer_shell), |acc, c| acc - c)
        .build()
        .and_then(|solid| solid.clean())
        .map(|solid| solid.translate(DVec3::Z * (-RAIL_CROSS_HEIGHT / 2.0)))
}

fn frame() -> Result<Vec<Solid>, cadrum::Error> {
    let side_y = FRAME_WIDTH / 2.0 - RAIL_CROSS_WIDTH / 2.0;
    let front_x = FRAME_LENGTH / 2.0 - RAIL_CROSS_WIDTH / 2.0;
    let rear_x = -FRAME_LENGTH / 2.0 + RAIL_CROSS_WIDTH / 2.0;
    let cross_length = FRAME_WIDTH - 2.0 * RAIL_CROSS_WIDTH;

    let side_rail = perforated_rail(FRAME_LENGTH)?;
    let cross_rail = perforated_rail(cross_length)?.rotate_z(FRAC_PI_2);

    Ok([
        side_rail.clone().translate(DVec3::new(0.0, side_y, FRAME_TOP_Z)),
        side_rail.translate(DVec3::new(0.0, -side_y, FRAME_TOP_Z)),
        cross_rail.clone().translate(DVec3::new(front_x, 0.0, FRAME_TOP_Z)),
        cross_rail.translate(DVec3::new(rear_x, 0.0, FRAME_TOP_Z)),
    ]
    .into_iter()
    .map(|rail| rail.paint(ALUMINUM_COLOR))
    .collect())
}

fn vertical_posts() -> Result<Vec<Solid>, cadrum::Error> {
    let post_template = perforated_rail(POST_HEIGHT)?
        .translate(DVec3::Z * (RAIL_CROSS_HEIGHT / 2.0))
        .rotate_y(-FRAC_PI_2);
    let post_x_extent = FRAME_LENGTH / 2.0 - POST_INSET_FROM_END;
    let post_y = FRAME_WIDTH / 2.0 - RAIL_CROSS_WIDTH / 2.0;
    let post_z_center = FRAME_TOP_Z + POST_HEIGHT / 2.0;

    let mut parts = Vec::with_capacity(4);
    for post_x in [-post_x_extent, post_x_extent] {
        for post_y_sign in [1.0, -1.0] {
            parts.push(
                post_template
                    .clone()
                    .translate(DVec3::new(post_x, post_y_sign * post_y, post_z_center))
                    .paint(ALUMINUM_COLOR),
            );
        }
    }
    Ok(parts)
}

fn outer_face_gusset() -> Result<Solid, cadrum::Error> {
    let half_width = GUSSET_ARM_WIDTH / 2.0;

    let vertical_arm = Solid::cube(
        DVec3::new(-half_width, 0.0, -half_width),
        DVec3::new(half_width, GUSSET_THICKNESS, GUSSET_ARM_LENGTH),
    );
    let horizontal_arm = Solid::cube(
        DVec3::new(-half_width, 0.0, -RAIL_CROSS_HEIGHT),
        DVec3::new(GUSSET_ARM_LENGTH, GUSSET_THICKNESS, 0.0),
    );
    let l_shape = (&vertical_arm + &horizontal_arm).build()?;

    let hole_radius = GUSSET_HOLE_DIAMETER / 2.0;
    let cutter_axis = DVec3::Y * (GUSSET_THICKNESS + 2.0 * CUTTER_OVERSHOOT_MM);
    let cutter_y_start = -CUTTER_OVERSHOOT_MM;

    let mut cutters: Vec<Solid> = Vec::new();
    for hole_index in 0..GUSSET_HOLES_PER_ARM {
        let z_offset = hole_index as f64 * GUSSET_HOLE_PITCH;
        cutters.push(
            Solid::cylinder(hole_radius, cutter_axis)
                .translate(DVec3::new(0.0, cutter_y_start, z_offset)),
        );
    }
    for hole_index in 1..GUSSET_HOLES_PER_ARM {
        let x_offset = hole_index as f64 * GUSSET_HOLE_PITCH;
        cutters.push(
            Solid::cylinder(hole_radius, cutter_axis)
                .translate(DVec3::new(x_offset, cutter_y_start, -RAIL_CROSS_HEIGHT / 2.0)),
        );
    }

    cutters
        .iter()
        .map(Boolean::from)
        .fold(Boolean::from(&l_shape), |acc, c| acc - c)
        .build()
        .and_then(|solid| solid.clean())
}

fn post_gussets() -> Result<Vec<Solid>, Box<dyn Error>> {
    let gusset_template = outer_face_gusset()?;

    let post_x_extent = FRAME_LENGTH / 2.0 - POST_INSET_FROM_END;
    let post_center_y = FRAME_WIDTH / 2.0 - RAIL_CROSS_WIDTH / 2.0;

    let mut gussets = Vec::with_capacity(8);
    for post_x_sign in [1.0, -1.0] {
        for post_y_sign in [1.0, -1.0] {
            let post_x = post_x_sign * post_x_extent;
            let post_outer_face_y =
                post_y_sign * post_center_y + post_y_sign * (RAIL_CROSS_WIDTH / 2.0);
            for x_side_sign in [1.0, -1.0] {
                let mut gusset = gusset_template.clone();
                if x_side_sign < 0.0 {
                    gusset = gusset.mirror(DVec3::ZERO, DVec3::X);
                }
                if post_y_sign < 0.0 {
                    gusset = gusset.mirror(DVec3::ZERO, DVec3::Y);
                }
                gussets.push(
                    gusset
                        .translate(DVec3::new(post_x, post_outer_face_y, FRAME_TOP_Z))
                        .paint(STEEL_COLOR),
                );
            }
        }
    }
    Ok(gussets)
}

fn corner_gusset() -> Result<Solid, cadrum::Error> {
    let half_width = GUSSET_ARM_WIDTH / 2.0;
    let arm_x = Solid::cube(
        DVec3::new(-half_width, -half_width, -GUSSET_THICKNESS),
        DVec3::new(GUSSET_ARM_LENGTH, half_width, 0.0),
    );
    let arm_y = Solid::cube(
        DVec3::new(-half_width, -GUSSET_ARM_LENGTH, -GUSSET_THICKNESS),
        DVec3::new(half_width, half_width, 0.0),
    );
    let l_shape = (&arm_x + &arm_y).build()?;

    let hole_radius = GUSSET_HOLE_DIAMETER / 2.0;
    let hole_axis = DVec3::Z * (GUSSET_THICKNESS + 2.0 * CUTTER_OVERSHOOT_MM);
    let hole_z_bottom = -GUSSET_THICKNESS - CUTTER_OVERSHOOT_MM;

    let mut cutters: Vec<Solid> = Vec::with_capacity(GUSSET_HOLES_PER_ARM * 2 - 1);
    for arm_index in 0..GUSSET_HOLES_PER_ARM {
        let offset = arm_index as f64 * GUSSET_HOLE_PITCH;
        cutters.push(
            Solid::cylinder(hole_radius, hole_axis)
                .translate(DVec3::new(offset, 0.0, hole_z_bottom)),
        );
    }
    for arm_index in 1..GUSSET_HOLES_PER_ARM {
        let offset = arm_index as f64 * GUSSET_HOLE_PITCH;
        cutters.push(
            Solid::cylinder(hole_radius, hole_axis)
                .translate(DVec3::new(0.0, -offset, hole_z_bottom)),
        );
    }

    cutters
        .iter()
        .map(Boolean::from)
        .fold(Boolean::from(&l_shape), |acc, c| acc - c)
        .build()
        .and_then(|solid| solid.clean())
        .map(|solid| solid.translate(DVec3::Z * GUSSET_THICKNESS))
}

fn rail_end_cap() -> Result<Solid, cadrum::Error> {
    let flange_half_y = RAIL_CROSS_WIDTH / 2.0;
    let flange_half_z = RAIL_CROSS_HEIGHT / 2.0;
    let boss_half_y = flange_half_y - RAIL_WALL_THICKNESS;
    let boss_half_z = flange_half_z - RAIL_WALL_THICKNESS;
    let cavity_half_y = boss_half_y - RAIL_END_CAP_BOSS_WALL;
    let cavity_half_z = boss_half_z - RAIL_END_CAP_BOSS_WALL;
    let flange_thickness = RAIL_END_CAP_FLANGE_THICKNESS;
    let boss_depth = RAIL_END_CAP_BOSS_DEPTH;

    let flange = Solid::cube(
        DVec3::new(-flange_thickness, -flange_half_y, -flange_half_z),
        DVec3::new(0.0, flange_half_y, flange_half_z),
    );
    let boss = Solid::cube(
        DVec3::new(0.0, -boss_half_y, -boss_half_z),
        DVec3::new(boss_depth, boss_half_y, boss_half_z),
    );
    let cavity = Solid::cube(
        DVec3::new(-CAVITY_OVERSHOOT_MM, -cavity_half_y, -cavity_half_z),
        DVec3::new(boss_depth + CAVITY_OVERSHOOT_MM, cavity_half_y, cavity_half_z),
    );

    let shell = (&flange + &boss).build()?;
    (&shell - &cavity).build().and_then(|solid| solid.clean())
}

fn rail_end_caps() -> Result<Vec<Solid>, cadrum::Error> {
    let end_cap_template = rail_end_cap()?.paint(END_CAP_COLOR);

    let rail_center_z = FRAME_TOP_Z - RAIL_CROSS_HEIGHT / 2.0;
    let side_y = FRAME_WIDTH / 2.0 - RAIL_CROSS_WIDTH / 2.0;
    let rear_x_outer = -FRAME_LENGTH / 2.0;
    let front_x_outer = FRAME_LENGTH / 2.0;

    let placements = [
        (0.0, rear_x_outer, side_y),
        (PI, front_x_outer, side_y),
        (0.0, rear_x_outer, -side_y),
        (PI, front_x_outer, -side_y),
    ];

    Ok(placements
        .iter()
        .map(|&(z_rot, x, y)| {
            end_cap_template.clone().rotate_z(z_rot).translate(DVec3::new(x, y, rail_center_z))
        })
        .collect())
}

fn gussets() -> Result<Vec<Solid>, Box<dyn Error>> {
    let gusset_template = corner_gusset()?.paint(STEEL_COLOR);

    let rear_outer_x = -FRAME_LENGTH / 2.0;
    let front_outer_x = FRAME_LENGTH / 2.0;
    let outer_y = FRAME_WIDTH / 2.0;
    let inset = RAIL_HOLE_SPACING;

    let corners = [
        (0.0, rear_outer_x + inset, outer_y - inset),
        (FRAC_PI_2, rear_outer_x + inset, -outer_y + inset),
        (PI, front_outer_x - inset, -outer_y + inset),
        (-FRAC_PI_2, front_outer_x - inset, outer_y - inset),
    ];

    Ok(corners
        .iter()
        .map(|&(z_rot, x, y)| {
            gusset_template.clone().rotate_z(z_rot).translate(DVec3::new(x, y, FRAME_TOP_Z))
        })
        .collect())
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

fn place_step_centered_and_grounded(
    asset_name: &str,
    position: DVec3,
    orient: impl Fn(Solid) -> Solid,
) -> Result<Vec<Solid>, Box<dyn Error>> {
    let imported_solids = Solid::read_step(&mut File::open(asset(asset_name))?)?;
    let oriented: Vec<Solid> = imported_solids.into_iter().map(orient).collect();
    let [min, max] = combined_bounds(&oriented);
    let footprint = DVec3::new((min.x + max.x) / 2.0, (min.y + max.y) / 2.0, min.z);
    Ok(oriented
        .into_iter()
        .map(|solid| solid.translate(-footprint).translate(position))
        .collect())
}

fn battery_assembly() -> Result<Vec<Solid>, Box<dyn Error>> {
    let deck_top_z = FRAME_TOP_Z;
    let battery_center_x = -300.0;

    let imported = Solid::read_step(&mut File::open(asset("12v-sla-battery.step"))?)?;
    let [raw_min, raw_max] = combined_bounds(&imported);
    let footprint = DVec3::new(
        (raw_min.x + raw_max.x) / 2.0,
        (raw_min.y + raw_max.y) / 2.0,
        raw_min.z,
    );
    let battery_size = raw_max - raw_min;
    let battery_top_z = deck_top_z + battery_size.z;

    let mut parts: Vec<Solid> = imported
        .into_iter()
        .map(|solid| {
            solid.translate(-footprint).translate(DVec3::Z * deck_top_z).paint(BATTERY_COLOR)
        })
        .collect();

    let strap_length = battery_size.x + 2.0 * BATTERY_STRAP_OVERHANG;
    let strap_z_center = battery_top_z + BATTERY_STRAP_THICKNESS / 2.0;
    for strap_offset in [-BATTERY_STRAP_X_SPACING / 2.0, BATTERY_STRAP_X_SPACING / 2.0] {
        parts.push(box_centered(
            DVec3::new(strap_length, BATTERY_STRAP_WIDTH, BATTERY_STRAP_THICKNESS),
            DVec3::new(0.0, strap_offset, strap_z_center),
        ).paint(ALUMINUM_COLOR));
    }

    let anchor_x = battery_size.x / 2.0 + BATTERY_STRAP_OVERHANG;
    let deck_bottom_z = deck_top_z - RAIL_CROSS_HEIGHT;
    let shaft_bottom_z = deck_bottom_z - BATTERY_ANCHOR_NUT_HEIGHT;
    let bolt_top_z = battery_top_z + BATTERY_STRAP_THICKNESS;
    let shaft_axis = DVec3::Z * (bolt_top_z - shaft_bottom_z);
    let head_axis = DVec3::Z * BATTERY_ANCHOR_HEAD_HEIGHT;
    let nut_axis = DVec3::Z * BATTERY_ANCHOR_NUT_HEIGHT;
    for strap_offset in [-BATTERY_STRAP_X_SPACING / 2.0, BATTERY_STRAP_X_SPACING / 2.0] {
        for anchor_offset in [-anchor_x, anchor_x] {
            parts.push(
                Solid::cylinder(BATTERY_ANCHOR_BOLT_DIAMETER / 2.0, shaft_axis)
                    .translate(DVec3::new(anchor_offset, strap_offset, shaft_bottom_z))
                    .paint(STEEL_COLOR),
            );
            parts.push(
                Solid::cylinder(BATTERY_ANCHOR_HEAD_DIAMETER / 2.0, head_axis)
                    .translate(DVec3::new(anchor_offset, strap_offset, bolt_top_z))
                    .paint(STEEL_COLOR),
            );
            parts.push(
                Solid::cylinder(BATTERY_ANCHOR_NUT_DIAMETER / 2.0, nut_axis)
                    .translate(DVec3::new(anchor_offset, strap_offset, shaft_bottom_z))
                    .paint(STEEL_COLOR),
            );
        }
    }

    Ok(parts
        .into_iter()
        .map(|s| s.rotate_z(FRAC_PI_2).translate(DVec3::new(battery_center_x, 0.0, 0.0)))
        .collect())
}

fn deck_parts() -> Result<Vec<Solid>, Box<dyn Error>> {
    let top = FRAME_TOP_Z;
    let mut parts = battery_assembly()?;
    parts.extend(place_step_centered_and_grounded(
        "cytron-hat-md30c.STEP",
        DVec3::new(-300.0, 200.0, top),
        |solid| solid.rotate_z(PI),
    )?);
    parts.extend(place_step_centered_and_grounded(
        "cytron-hat-md30c.STEP",
        DVec3::new(-300.0, -200.0, top),
        |solid| solid,
    )?);
    parts.extend(place_step_centered_and_grounded(
        "breadboard-3220-pin-assembly.step",
        DVec3::new(300.0, 0.0, top),
        |solid| solid.rotate_z(-FRAC_PI_2),
    )?);
    parts.extend(place_step_top_centered_and_ceiling(
        "hc-sr04-ultrasonic-sensor.step",
        DVec3::new(FRAME_LENGTH / 2.0 + 10.0, 0.0, top),
        |solid| solid.rotate_y(FRAC_PI_2).rotate_x(FRAC_PI_2),
    )?);
    parts.extend(place_step_top_centered_and_ceiling(
        "hc-sr04-ultrasonic-sensor.step",
        DVec3::new(-FRAME_LENGTH / 2.0 - 10.0, 0.0, top),
        |solid| solid.rotate_y(FRAC_PI_2).rotate_x(FRAC_PI_2).rotate_z(PI),
    )?);
    parts.extend(place_step_centered_and_grounded(
        "nucleo_h755zi_q.step",
        DVec3::new(150.0, 200.0, top),
        |solid| solid.rotate_z(-FRAC_PI_2),
    )?);
    parts.extend(place_step_centered_and_grounded(
        "rpi5.step",
        DVec3::new(150.0, -150.0, top),
        |solid| solid.rotate_x(FRAC_PI_2),
    )?);
    Ok(parts)
}

fn place_step_top_centered_and_ceiling(
    asset_name: &str,
    position: DVec3,
    orient: impl Fn(Solid) -> Solid,
) -> Result<Vec<Solid>, Box<dyn Error>> {
    let imported_solids = Solid::read_step(&mut File::open(asset(asset_name))?)?;
    let oriented: Vec<Solid> = imported_solids.into_iter().map(orient).collect();
    let [min, max] = combined_bounds(&oriented);
    let anchor = DVec3::new((min.x + max.x) / 2.0, (min.y + max.y) / 2.0, max.z);
    Ok(oriented
        .into_iter()
        .map(|solid| solid.translate(-anchor).translate(position))
        .collect())
}

fn max_bbox_dim(solid: &Solid) -> f64 {
    let [min, max] = solid.bounding_box();
    let extents = max - min;
    extents.x.max(extents.y).max(extents.z)
}

fn drive_wheels() -> Result<Vec<Solid>, Box<dyn Error>> {
    let imported_solids = Solid::read_step(&mut File::open(asset(DRIVE_WHEEL_STEP_FILENAME))?)?;
    let center = bounding_center(&imported_solids);

    let tire_index = imported_solids
        .iter()
        .enumerate()
        .max_by(|(_, a), (_, b)| max_bbox_dim(a).partial_cmp(&max_bbox_dim(b)).unwrap())
        .map(|(i, _)| i);

    let [wheel_bbox_min, wheel_bbox_max] = combined_bounds(&imported_solids);
    let wheel_bbox_extent_pos_x = wheel_bbox_max.x - center.x;
    let wheel_bbox_extent_neg_x = center.x - wheel_bbox_min.x;
    let frame_rear_x = -FRAME_LENGTH / 2.0;
    let frame_front_x = FRAME_LENGTH / 2.0;
    let axle_x_positions = [
        frame_rear_x + wheel_bbox_extent_neg_x,
        frame_front_x - wheel_bbox_extent_pos_x,
    ];
    let mut wheels =
        Vec::with_capacity(imported_solids.len() * 2 * axle_x_positions.len());
    for &axle_x in &axle_x_positions {
        for (body_index, solid) in imported_solids.iter().enumerate() {
            let is_tire = Some(body_index) == tire_index;
            let wheel_body = if is_tire {
                solid.clone().paint(TIRE_COLOR)
            } else {
                solid.clone()
            };
            wheels.push(
                wheel_body
                    .clone()
                    .translate(-center)
                    .translate(DVec3::new(axle_x, -DRIVE_WHEEL_TRACK / 2.0, WHEEL_RADIUS)),
            );
            wheels.push(
                wheel_body
                    .translate(-center)
                    .mirror(DVec3::ZERO, DVec3::Y)
                    .translate(DVec3::new(axle_x, DRIVE_WHEEL_TRACK / 2.0, WHEEL_RADIUS)),
            );
        }
    }
    Ok(wheels)
}

fn robot() -> Result<Vec<Solid>, Box<dyn Error>> {
    let mut parts = Vec::new();
    parts.push(plank());
    parts.extend(frame()?);
    parts.extend(gussets()?);
    parts.extend(rail_end_caps()?);
    parts.extend(vertical_posts()?);
    parts.extend(post_gussets()?);
    parts.extend(drive_wheels()?);
    parts.extend(deck_parts()?);
    Ok(parts)
}

fn material_props_for(color: [u8; 3]) -> MaterialProps {
    match color {
        ALUMINUM_COLOR => MaterialProps { metallic: 0.6, roughness: 0.55 },
        STEEL_COLOR => MaterialProps { metallic: 0.35, roughness: 0.75 },
        WHEEL_BRACKET_COLOR => MaterialProps { metallic: 0.25, roughness: 0.65 },
        END_CAP_COLOR => MaterialProps { metallic: 0.0, roughness: 0.6 },
        PLYWOOD_COLOR => MaterialProps { metallic: 0.0, roughness: 0.9 },
        TIRE_COLOR => MaterialProps { metallic: 0.0, roughness: 0.95 },
        BATTERY_COLOR => MaterialProps { metallic: 0.0, roughness: 0.9 },
        _ => MaterialProps { metallic: 0.3, roughness: 0.7 },
    }
}

fn density_kg_per_m3_for(color: [u8; 3]) -> f64 {
    match color {
        ALUMINUM_COLOR | WHEEL_BRACKET_COLOR => ALUMINUM_DENSITY_KG_PER_M3,
        STEEL_COLOR => STEEL_DENSITY_KG_PER_M3,
        END_CAP_COLOR => PLASTIC_DENSITY_KG_PER_M3,
        PLYWOOD_COLOR => PLYWOOD_DENSITY_KG_PER_M3,
        TIRE_COLOR => RUBBER_DENSITY_KG_PER_M3,
        BATTERY_COLOR => SLA_BATTERY_DENSITY_KG_PER_M3,
        _ => STEEL_DENSITY_KG_PER_M3,
    }
}

fn material_name_for(color: [u8; 3]) -> &'static str {
    match color {
        ALUMINUM_COLOR => "aluminum",
        WHEEL_BRACKET_COLOR => "aluminum",
        STEEL_COLOR => "steel",
        END_CAP_COLOR => "plastic",
        PLYWOOD_COLOR => "plywood",
        TIRE_COLOR => "rubber",
        BATTERY_COLOR => "sla-battery",
        _ => "steel(default)",
    }
}

fn dominant_color_key(solid: &Solid) -> [u8; 3] {
    let mut counts: HashMap<[u8; 3], usize> = HashMap::new();
    for color in solid.colormap().values() {
        let key = [
            (color.r.clamp(0.0, 1.0) * 255.0) as u8,
            (color.g.clamp(0.0, 1.0) * 255.0) as u8,
            (color.b.clamp(0.0, 1.0) * 255.0) as u8,
        ];
        *counts.entry(key).or_insert(0) += 1;
    }
    counts
        .into_iter()
        .max_by_key(|(_, count)| *count)
        .map(|(key, _)| key)
        .unwrap_or(ALUMINUM_COLOR)
}

fn report_geometry_table(solids: &[Solid]) {
    const CUBIC_MM_TO_CUBIC_M: f64 = 1e-9;
    println!(
        "{:>3} {:>14} {:>12} {:>10} {:>36} {:>30}",
        "id", "material", "volume mm³", "mass kg", "center xyz mm", "bbox size mm"
    );
    let mut total_mass = 0.0;
    for (index, solid) in solids.iter().enumerate() {
        let volume = solid.volume().abs();
        let color = dominant_color_key(solid);
        let material = material_name_for(color);
        let density = density_kg_per_m3_for(color);
        let mass = volume * CUBIC_MM_TO_CUBIC_M * density;
        total_mass += mass;
        let center = solid.center();
        let [bmin, bmax] = solid.bounding_box();
        let size = bmax - bmin;
        println!(
            "{:>3} {:>14} {:>12.3e} {:>10.4} {:>10.1}, {:>10.1}, {:>10.1} {:>8.1} × {:>8.1} × {:>8.1}",
            index, material, volume, mass,
            center.x, center.y, center.z, size.x, size.y, size.z,
        );
    }
    println!("total assembly mass: {:.3} kg", total_mass);
}

fn main() -> Result<(), Box<dyn Error>> {
    let output_directory = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets");
    fs::create_dir_all(&output_directory)?;

    let solids = robot()?;
    report_geometry_table(&solids);

    let glb_path = output_directory.join("robot.glb");
    let gltf_solids: Vec<Solid> =
        solids.iter().cloned().map(|solid| solid.align_z(DVec3::Y, DVec3::X)).collect();
    let gltf_mesh = Solid::mesh(&gltf_solids, Tessellation { deflection_linear: 0.001, deflection_angular: 0.05, relative_linear: true })?;
    write_lit_gltf(&gltf_mesh, material_props_for, &mut File::create(&glb_path)?)?;

    println!("wrote {}", glb_path.display());
    Ok(())
}
