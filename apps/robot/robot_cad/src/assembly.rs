use std::{
    error::Error,
    f64::consts::{FRAC_PI_2, PI},
    fs::File,
};

use cadrum::{Boolean, DVec3, Solid};
use robot_description::{
    datums::{
        MOTOR_MOUNT_WIDTH_MM, WHEEL_HUB_INBOARD_FACE_FROM_STEP_ORIGIN_MM, WHEEL_TREAD_DIAMETER_MM,
        WHEEL_TREAD_WIDTH_MM,
    },
    parameters::{
        BATTERY_ANCHOR_BOLT_DIAMETER_MM, BATTERY_ANCHOR_HEAD_DIAMETER_MM,
        BATTERY_ANCHOR_HEAD_HEIGHT_MM, BATTERY_ANCHOR_NUT_DIAMETER_MM,
        BATTERY_ANCHOR_NUT_HEIGHT_MM, BATTERY_PACK_CENTER_X_MM, BATTERY_PAIR_GAP_MM,
        BATTERY_STRAP_OVERHANG_MM, BATTERY_STRAP_PAIR_SPACING_MM, BATTERY_STRAP_THICKNESS_MM,
        BATTERY_STRAP_WIDTH_MM, FRAME_LENGTH_MM, FRAME_TOP_Z_MM, FRAME_WIDTH_MM,
        GUSSET_ARM_LENGTH_MM, GUSSET_ARM_WIDTH_MM, GUSSET_HOLES_PER_ARM, GUSSET_HOLE_DIAMETER_MM,
        GUSSET_HOLE_PITCH_MM, GUSSET_THICKNESS_MM, MOTOR_CONTROLLER_OFFSET_Y_MM, POST_HEIGHT_MM,
        POST_INSET_FROM_END_MM, RAIL_CROSS_HEIGHT_MM, RAIL_CROSS_WIDTH_MM,
        RAIL_END_CAP_BOSS_DEPTH_MM, RAIL_END_CAP_BOSS_WALL_MM, RAIL_END_CAP_FLANGE_THICKNESS_MM,
        RAIL_FILLET_RADIUS_MM, RAIL_HOLE_DIAMETER_MM, RAIL_HOLE_SPACING_MM, RAIL_WALL_THICKNESS_MM,
        ULTRASONIC_OUTBOARD_OFFSET_MM,
    },
    placement::{self, Corner, Side},
};

use crate::{
    asset,
    material::{Material, WithMaterial},
    time_it, Link, LinkId,
};

const EDGE_COINCIDENCE_EPSILON_MM: f64 = 1e-6;
const CUTTER_OVERSHOOT_MM: f64 = 1.0;
const CAVITY_OVERSHOOT_MM: f64 = 0.5;
const DATUM_TOLERANCE_MM: f64 = 1e-3;

pub const WHEEL_TREAD_STEP: &str = "14in_wheel_tread.step";
pub const WHEEL_RIM_STEP: &str = "14in_wheel_rim.step";
pub const WHEEL_HUB_STEP: &str = "14in_wheel_four_bolt_hub_flange_with_boss.step";
pub const MOTOR_MOUNT_STEP: &str = "motor-mount.step";
pub const DRIVE_MOTOR_STEP: &str = "24v-drive-motor.step";

fn box_centered(size: DVec3, center: DVec3) -> Solid {
    Solid::cube(center - size / 2.0, center + size / 2.0)
}

fn plank() -> Solid {
    let plank_length = FRAME_LENGTH_MM - 2.0 * RAIL_CROSS_WIDTH_MM;
    let plank_width = FRAME_WIDTH_MM - 2.0 * RAIL_CROSS_WIDTH_MM;
    let plank_z_center = FRAME_TOP_Z_MM - RAIL_CROSS_HEIGHT_MM / 2.0;
    box_centered(
        DVec3::new(plank_length, plank_width, RAIL_CROSS_HEIGHT_MM),
        DVec3::new(0.0, 0.0, plank_z_center),
    )
    .with_material(Material::Plywood)
}

fn perforated_rail(length: f64) -> Result<Solid, cadrum::Error> {
    let half_x = length / 2.0;
    let half_y = RAIL_CROSS_WIDTH_MM / 2.0;
    let half_z = RAIL_CROSS_HEIGHT_MM / 2.0;
    let hole_radius = RAIL_HOLE_DIAMETER_MM / 2.0;

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
    let filleted_block =
        outer_block.fillet_edges(RAIL_FILLET_RADIUS_MM, longitudinal_corner_edges)?;

    let end_slab_x = half_x - RAIL_FILLET_RADIUS_MM - EDGE_COINCIDENCE_EPSILON_MM;
    let end_faces: Vec<&cadrum::Face> = filleted_block
        .iter_face()
        .filter(|face| {
            let endpoints: Vec<DVec3> = face
                .iter_edge()
                .flat_map(|edge| [edge.start_point(), edge.end_point()])
                .collect();
            endpoints.iter().all(|point| point.x >= end_slab_x)
                || endpoints.iter().all(|point| point.x <= -end_slab_x)
        })
        .collect();
    let outer_shell = filleted_block.shell(-RAIL_WALL_THICKNESS_MM, end_faces)?;

    let hole_count = (length / RAIL_HOLE_SPACING_MM).round() as usize;
    let first_hole_x = -((hole_count as f64 - 1.0) * RAIL_HOLE_SPACING_MM) / 2.0;
    let wide_face_row_y_offset = RAIL_HOLE_SPACING_MM;
    let top_bottom_hole_cutter_axis = DVec3::Z * (RAIL_CROSS_HEIGHT_MM + 2.0 * CUTTER_OVERSHOOT_MM);
    let side_hole_cutter_axis = DVec3::Y * (RAIL_CROSS_WIDTH_MM + 2.0 * CUTTER_OVERSHOOT_MM);

    let mut cutters: Vec<Solid> = Vec::new();
    for hole_index in 0..hole_count {
        let x = first_hole_x + hole_index as f64 * RAIL_HOLE_SPACING_MM;
        for &y_row in &[-wide_face_row_y_offset, wide_face_row_y_offset] {
            cutters.push(
                Solid::cylinder(hole_radius, top_bottom_hole_cutter_axis).translate(DVec3::new(
                    x,
                    y_row,
                    -half_z - CUTTER_OVERSHOOT_MM,
                )),
            );
        }
        cutters.push(
            Solid::cylinder(hole_radius, side_hole_cutter_axis).translate(DVec3::new(
                x,
                -half_y - CUTTER_OVERSHOOT_MM,
                0.0,
            )),
        );
    }

    cutters
        .iter()
        .fold(Boolean::from(&outer_shell), |acc, c| acc - c)
        .build()
        .and_then(|solid| solid.clean())
        .map(|solid| solid.translate(DVec3::Z * (-RAIL_CROSS_HEIGHT_MM / 2.0)))
}

fn frame() -> Result<Vec<Solid>, cadrum::Error> {
    let side_y = FRAME_WIDTH_MM / 2.0 - RAIL_CROSS_WIDTH_MM / 2.0;
    let front_x = FRAME_LENGTH_MM / 2.0 - RAIL_CROSS_WIDTH_MM / 2.0;
    let rear_x = -FRAME_LENGTH_MM / 2.0 + RAIL_CROSS_WIDTH_MM / 2.0;
    let cross_length = FRAME_WIDTH_MM - 2.0 * RAIL_CROSS_WIDTH_MM;

    let side_rail = perforated_rail(FRAME_LENGTH_MM)?;
    let cross_rail = perforated_rail(cross_length)?.rotate_z(FRAC_PI_2);

    Ok([
        side_rail
            .clone()
            .translate(DVec3::new(0.0, side_y, FRAME_TOP_Z_MM)),
        side_rail.translate(DVec3::new(0.0, -side_y, FRAME_TOP_Z_MM)),
        cross_rail
            .clone()
            .translate(DVec3::new(front_x, 0.0, FRAME_TOP_Z_MM)),
        cross_rail.translate(DVec3::new(rear_x, 0.0, FRAME_TOP_Z_MM)),
    ]
    .into_iter()
    .map(|rail| rail.with_material(Material::Aluminum))
    .collect())
}

fn vertical_posts() -> Result<Vec<Solid>, cadrum::Error> {
    let post_template = perforated_rail(POST_HEIGHT_MM)?
        .translate(DVec3::Z * (RAIL_CROSS_HEIGHT_MM / 2.0))
        .rotate_y(-FRAC_PI_2);
    let post_x_extent = FRAME_LENGTH_MM / 2.0 - POST_INSET_FROM_END_MM;
    let post_y = FRAME_WIDTH_MM / 2.0 - RAIL_CROSS_WIDTH_MM / 2.0;
    let post_z_center = FRAME_TOP_Z_MM + POST_HEIGHT_MM / 2.0;

    let mut parts = Vec::with_capacity(4);
    for post_x in [-post_x_extent, post_x_extent] {
        for post_y_sign in [1.0, -1.0] {
            parts.push(
                post_template
                    .clone()
                    .translate(DVec3::new(post_x, post_y_sign * post_y, post_z_center))
                    .with_material(Material::Aluminum),
            );
        }
    }
    Ok(parts)
}

fn outer_face_gusset() -> Result<Solid, cadrum::Error> {
    let half_width = GUSSET_ARM_WIDTH_MM / 2.0;

    let vertical_arm = Solid::cube(
        DVec3::new(-half_width, 0.0, -half_width),
        DVec3::new(half_width, GUSSET_THICKNESS_MM, GUSSET_ARM_LENGTH_MM),
    );
    let horizontal_arm = Solid::cube(
        DVec3::new(-half_width, 0.0, -RAIL_CROSS_HEIGHT_MM),
        DVec3::new(GUSSET_ARM_LENGTH_MM, GUSSET_THICKNESS_MM, 0.0),
    );
    let l_shape = (&vertical_arm + &horizontal_arm).build()?;

    let hole_radius = GUSSET_HOLE_DIAMETER_MM / 2.0;
    let cutter_axis = DVec3::Y * (GUSSET_THICKNESS_MM + 2.0 * CUTTER_OVERSHOOT_MM);
    let cutter_y_start = -CUTTER_OVERSHOOT_MM;

    let mut cutters: Vec<Solid> = Vec::new();
    for hole_index in 0..GUSSET_HOLES_PER_ARM {
        let z_offset = hole_index as f64 * GUSSET_HOLE_PITCH_MM;
        cutters.push(
            Solid::cylinder(hole_radius, cutter_axis).translate(DVec3::new(
                0.0,
                cutter_y_start,
                z_offset,
            )),
        );
    }
    for hole_index in 1..GUSSET_HOLES_PER_ARM {
        let x_offset = hole_index as f64 * GUSSET_HOLE_PITCH_MM;
        cutters.push(
            Solid::cylinder(hole_radius, cutter_axis).translate(DVec3::new(
                x_offset,
                cutter_y_start,
                -RAIL_CROSS_HEIGHT_MM / 2.0,
            )),
        );
    }

    cutters
        .iter()
        .fold(Boolean::from(&l_shape), |acc, c| acc - c)
        .build()
        .and_then(|solid| solid.clean())
}

fn post_gussets() -> Result<Vec<Solid>, Box<dyn Error>> {
    let gusset_template = outer_face_gusset()?;

    let post_x_extent = FRAME_LENGTH_MM / 2.0 - POST_INSET_FROM_END_MM;
    let post_center_y = FRAME_WIDTH_MM / 2.0 - RAIL_CROSS_WIDTH_MM / 2.0;

    let mut gussets = Vec::with_capacity(8);
    for post_x_sign in [1.0, -1.0] {
        for post_y_sign in [1.0, -1.0] {
            let post_x = post_x_sign * post_x_extent;
            let post_outer_face_y =
                post_y_sign * post_center_y + post_y_sign * (RAIL_CROSS_WIDTH_MM / 2.0);
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
                        .translate(DVec3::new(post_x, post_outer_face_y, FRAME_TOP_Z_MM))
                        .with_material(Material::Steel),
                );
            }
        }
    }
    Ok(gussets)
}

fn corner_gusset() -> Result<Solid, cadrum::Error> {
    let half_width = GUSSET_ARM_WIDTH_MM / 2.0;
    let arm_x = Solid::cube(
        DVec3::new(-half_width, -half_width, -GUSSET_THICKNESS_MM),
        DVec3::new(GUSSET_ARM_LENGTH_MM, half_width, 0.0),
    );
    let arm_y = Solid::cube(
        DVec3::new(-half_width, -GUSSET_ARM_LENGTH_MM, -GUSSET_THICKNESS_MM),
        DVec3::new(half_width, half_width, 0.0),
    );
    let l_shape = (&arm_x + &arm_y).build()?;

    let hole_radius = GUSSET_HOLE_DIAMETER_MM / 2.0;
    let hole_axis = DVec3::Z * (GUSSET_THICKNESS_MM + 2.0 * CUTTER_OVERSHOOT_MM);
    let hole_z_bottom = -GUSSET_THICKNESS_MM - CUTTER_OVERSHOOT_MM;

    let mut cutters: Vec<Solid> = Vec::with_capacity(GUSSET_HOLES_PER_ARM * 2 - 1);
    for arm_index in 0..GUSSET_HOLES_PER_ARM {
        let offset = arm_index as f64 * GUSSET_HOLE_PITCH_MM;
        cutters.push(
            Solid::cylinder(hole_radius, hole_axis).translate(DVec3::new(
                offset,
                0.0,
                hole_z_bottom,
            )),
        );
    }
    for arm_index in 1..GUSSET_HOLES_PER_ARM {
        let offset = arm_index as f64 * GUSSET_HOLE_PITCH_MM;
        cutters.push(
            Solid::cylinder(hole_radius, hole_axis).translate(DVec3::new(
                0.0,
                -offset,
                hole_z_bottom,
            )),
        );
    }

    cutters
        .iter()
        .fold(Boolean::from(&l_shape), |acc, c| acc - c)
        .build()
        .and_then(|solid| solid.clean())
        .map(|solid| solid.translate(DVec3::Z * GUSSET_THICKNESS_MM))
}

fn rail_end_cap() -> Result<Solid, cadrum::Error> {
    let flange_half_y = RAIL_CROSS_WIDTH_MM / 2.0;
    let flange_half_z = RAIL_CROSS_HEIGHT_MM / 2.0;
    let boss_half_y = flange_half_y - RAIL_WALL_THICKNESS_MM;
    let boss_half_z = flange_half_z - RAIL_WALL_THICKNESS_MM;
    let cavity_half_y = boss_half_y - RAIL_END_CAP_BOSS_WALL_MM;
    let cavity_half_z = boss_half_z - RAIL_END_CAP_BOSS_WALL_MM;
    let flange_thickness = RAIL_END_CAP_FLANGE_THICKNESS_MM;
    let boss_depth = RAIL_END_CAP_BOSS_DEPTH_MM;

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
        DVec3::new(
            boss_depth + CAVITY_OVERSHOOT_MM,
            cavity_half_y,
            cavity_half_z,
        ),
    );

    let shell = (&flange + &boss).build()?;
    (&shell - &cavity).build().and_then(|solid| solid.clean())
}

fn rail_end_caps() -> Result<Vec<Solid>, cadrum::Error> {
    let end_cap_template = rail_end_cap()?.with_material(Material::Plastic);

    let rail_center_z = FRAME_TOP_Z_MM - RAIL_CROSS_HEIGHT_MM / 2.0;
    let side_y = FRAME_WIDTH_MM / 2.0 - RAIL_CROSS_WIDTH_MM / 2.0;
    let rear_x_outer = -FRAME_LENGTH_MM / 2.0;
    let front_x_outer = FRAME_LENGTH_MM / 2.0;

    let placements = [
        (0.0, rear_x_outer, side_y),
        (PI, front_x_outer, side_y),
        (0.0, rear_x_outer, -side_y),
        (PI, front_x_outer, -side_y),
    ];

    Ok(placements
        .iter()
        .map(|&(z_rot, x, y)| {
            end_cap_template
                .clone()
                .rotate_z(z_rot)
                .translate(DVec3::new(x, y, rail_center_z))
        })
        .collect())
}

fn post_caps() -> Result<Vec<Solid>, cadrum::Error> {
    let cap_template = rail_end_cap()?
        .rotate_y(FRAC_PI_2)
        .with_material(Material::Plastic);

    let post_x_extent = FRAME_LENGTH_MM / 2.0 - POST_INSET_FROM_END_MM;
    let post_y = FRAME_WIDTH_MM / 2.0 - RAIL_CROSS_WIDTH_MM / 2.0;
    let post_top_z = FRAME_TOP_Z_MM + POST_HEIGHT_MM;

    let mut caps = Vec::with_capacity(4);
    for post_x in [-post_x_extent, post_x_extent] {
        for post_y_sign in [1.0, -1.0] {
            caps.push(cap_template.clone().translate(DVec3::new(
                post_x,
                post_y_sign * post_y,
                post_top_z,
            )));
        }
    }
    Ok(caps)
}

fn gussets() -> Result<Vec<Solid>, Box<dyn Error>> {
    let gusset_template = corner_gusset()?.with_material(Material::Steel);

    let rear_outer_x = -FRAME_LENGTH_MM / 2.0;
    let front_outer_x = FRAME_LENGTH_MM / 2.0;
    let outer_y = FRAME_WIDTH_MM / 2.0;
    let inset = RAIL_HOLE_SPACING_MM;

    let corners = [
        (0.0, rear_outer_x + inset, outer_y - inset),
        (FRAC_PI_2, rear_outer_x + inset, -outer_y + inset),
        (PI, front_outer_x - inset, -outer_y + inset),
        (-FRAC_PI_2, front_outer_x - inset, outer_y - inset),
    ];

    Ok(corners
        .iter()
        .map(|&(z_rot, x, y)| {
            gusset_template
                .clone()
                .rotate_z(z_rot)
                .translate(DVec3::new(x, y, FRAME_TOP_Z_MM))
        })
        .collect())
}

fn combined_bounds(solids: &[Solid]) -> [DVec3; 2] {
    let init = (DVec3::splat(f64::INFINITY), DVec3::splat(f64::NEG_INFINITY));
    let (min, max) = solids
        .iter()
        .flat_map(|solid| solid.bounding_box())
        .fold(init, |(mn, mx), point| (mn.min(point), mx.max(point)));
    [min, max]
}

pub enum ZAnchor {
    Bottom,
    Top,
}

fn place_component(
    asset_name: &str,
    position: DVec3,
    z_anchor: ZAnchor,
    orient: impl Fn(Solid) -> Solid,
) -> Result<Vec<Solid>, Box<dyn Error>> {
    let imported_solids = Solid::read_step(&mut File::open(asset(asset_name))?)?;
    let oriented: Vec<Solid> = imported_solids.into_iter().map(orient).collect();
    let [min, max] = combined_bounds(&oriented);
    let anchor_z = match z_anchor {
        ZAnchor::Bottom => min.z,
        ZAnchor::Top => max.z,
    };
    let anchor = DVec3::new((min.x + max.x) / 2.0, (min.y + max.y) / 2.0, anchor_z);
    Ok(oriented
        .into_iter()
        .map(|solid| solid.translate(-anchor).translate(position))
        .collect())
}

fn battery_assembly() -> Result<Vec<Solid>, Box<dyn Error>> {
    let deck_top_z = FRAME_TOP_Z_MM;

    let imported = Solid::read_step(&mut File::open(asset("12v-sla-battery.step"))?)?;
    let oriented: Vec<Solid> = imported
        .into_iter()
        .map(|s| s.rotate_x(FRAC_PI_2))
        .collect();
    let [raw_min, raw_max] = combined_bounds(&oriented);
    let footprint = DVec3::new(
        (raw_min.x + raw_max.x) / 2.0,
        (raw_min.y + raw_max.y) / 2.0,
        raw_min.z,
    );
    let battery_size = raw_max - raw_min;
    let battery_top_z = deck_top_z + battery_size.z;
    let battery_y_offset = battery_size.y / 2.0 + BATTERY_PAIR_GAP_MM / 2.0;

    let mut parts: Vec<Solid> = Vec::new();
    for battery_y_sign in [1.0, -1.0] {
        parts.extend(oriented.iter().cloned().map(|solid| {
            solid
                .translate(-footprint)
                .translate(DVec3::new(
                    0.0,
                    battery_y_sign * battery_y_offset,
                    deck_top_z,
                ))
                .with_material(Material::SlaBattery)
        }));
    }

    let strap_length = 2.0 * battery_size.y + BATTERY_PAIR_GAP_MM + 2.0 * BATTERY_STRAP_OVERHANG_MM;
    let strap_z_center = battery_top_z + BATTERY_STRAP_THICKNESS_MM / 2.0;
    for strap_offset_x in [
        -BATTERY_STRAP_PAIR_SPACING_MM / 2.0,
        BATTERY_STRAP_PAIR_SPACING_MM / 2.0,
    ] {
        parts.push(
            box_centered(
                DVec3::new(
                    BATTERY_STRAP_WIDTH_MM,
                    strap_length,
                    BATTERY_STRAP_THICKNESS_MM,
                ),
                DVec3::new(strap_offset_x, 0.0, strap_z_center),
            )
            .with_material(Material::Aluminum),
        );
    }

    let anchor_y = battery_size.y + BATTERY_PAIR_GAP_MM / 2.0 + BATTERY_STRAP_OVERHANG_MM;
    let deck_bottom_z = deck_top_z - RAIL_CROSS_HEIGHT_MM;
    let shaft_bottom_z = deck_bottom_z - BATTERY_ANCHOR_NUT_HEIGHT_MM;
    let bolt_top_z = battery_top_z + BATTERY_STRAP_THICKNESS_MM;
    let shaft_axis = DVec3::Z * (bolt_top_z - shaft_bottom_z);
    let head_axis = DVec3::Z * BATTERY_ANCHOR_HEAD_HEIGHT_MM;
    let nut_axis = DVec3::Z * BATTERY_ANCHOR_NUT_HEIGHT_MM;
    for strap_offset_x in [
        -BATTERY_STRAP_PAIR_SPACING_MM / 2.0,
        BATTERY_STRAP_PAIR_SPACING_MM / 2.0,
    ] {
        for anchor_offset_y in [-anchor_y, anchor_y] {
            parts.push(
                Solid::cylinder(BATTERY_ANCHOR_BOLT_DIAMETER_MM / 2.0, shaft_axis)
                    .translate(DVec3::new(strap_offset_x, anchor_offset_y, shaft_bottom_z))
                    .with_material(Material::Steel),
            );
            parts.push(
                Solid::cylinder(BATTERY_ANCHOR_HEAD_DIAMETER_MM / 2.0, head_axis)
                    .translate(DVec3::new(strap_offset_x, anchor_offset_y, bolt_top_z))
                    .with_material(Material::Steel),
            );
            parts.push(
                Solid::cylinder(BATTERY_ANCHOR_NUT_DIAMETER_MM / 2.0, nut_axis)
                    .translate(DVec3::new(strap_offset_x, anchor_offset_y, shaft_bottom_z))
                    .with_material(Material::Steel),
            );
        }
    }

    Ok(parts
        .into_iter()
        .map(|s| s.translate(DVec3::new(BATTERY_PACK_CENTER_X_MM, 0.0, 0.0)))
        .collect())
}

fn deck_parts() -> Result<Vec<Solid>, Box<dyn Error>> {
    let top = FRAME_TOP_Z_MM;
    let mut parts = battery_assembly()?;
    parts.extend(place_component(
        "cytron-hat-md30c.STEP",
        DVec3::new(BATTERY_PACK_CENTER_X_MM, MOTOR_CONTROLLER_OFFSET_Y_MM, top),
        ZAnchor::Bottom,
        |solid| solid.rotate_z(PI),
    )?);
    parts.extend(place_component(
        "cytron-hat-md30c.STEP",
        DVec3::new(BATTERY_PACK_CENTER_X_MM, -MOTOR_CONTROLLER_OFFSET_Y_MM, top),
        ZAnchor::Bottom,
        |solid| solid,
    )?);
    // parts.extend(place_component(
    //     "breadboard-3220-pin-assembly.step",
    //     DVec3::new(BREADBOARD_CENTER_X_MM, 0.0, top),
    //     ZAnchor::Bottom,
    //     |solid| solid.rotate_z(-FRAC_PI_2),
    // )?);
    parts.extend(place_component(
        "hc-sr04-ultrasonic-sensor.step",
        DVec3::new(
            FRAME_LENGTH_MM / 2.0 + ULTRASONIC_OUTBOARD_OFFSET_MM,
            0.0,
            top,
        ),
        ZAnchor::Top,
        |solid| solid.rotate_y(FRAC_PI_2).rotate_x(FRAC_PI_2),
    )?);
    parts.extend(place_component(
        "hc-sr04-ultrasonic-sensor.step",
        DVec3::new(
            -FRAME_LENGTH_MM / 2.0 - ULTRASONIC_OUTBOARD_OFFSET_MM,
            0.0,
            top,
        ),
        ZAnchor::Top,
        |solid| solid.rotate_y(FRAC_PI_2).rotate_x(FRAC_PI_2).rotate_z(PI),
    )?);
    // parts.extend(place_component(
    //     "nucleo_h755zi_q.step",
    //     DVec3::new(NUCLEO_CENTER_X_MM, NUCLEO_OFFSET_Y_MM, top),
    //     ZAnchor::Bottom,
    //     |solid| solid.rotate_z(-FRAC_PI_2),
    // )?);
    // parts.extend(place_component(
    //     "rpi5.step",
    //     DVec3::new(RASPBERRY_PI_CENTER_X_MM, RASPBERRY_PI_OFFSET_Y_MM, top),
    //     ZAnchor::Bottom,
    //     |solid| solid.rotate_x(FRAC_PI_2),
    // )?);
    Ok(parts)
}

fn assert_datum(name: &str, declared: f64, measured: f64) {
    assert!(
        (declared - measured).abs() < DATUM_TOLERANCE_MM,
        "datum {name}: declared {declared}, measured {measured} — update description/src/datums.rs"
    );
}

pub struct MotorMountAssembly {
    mount_bodies: Vec<Solid>,
    motor_bodies: Vec<Solid>,
    mount_anchor: DVec3,
}

impl MotorMountAssembly {
    pub fn load() -> Result<Self, Box<dyn Error>> {
        let mount_bodies = Solid::read_step(&mut File::open(asset(MOTOR_MOUNT_STEP))?)?
            .into_iter()
            .map(|s| s.with_material(Material::AnodizedAluminum))
            .collect::<Vec<_>>();
        let [mount_min, mount_max] = combined_bounds(&mount_bodies);
        assert_datum(
            "MOTOR_MOUNT_WIDTH_MM",
            MOTOR_MOUNT_WIDTH_MM,
            mount_max.x - mount_min.x,
        );
        let mount_anchor = DVec3::new(
            (mount_min.x + mount_max.x) / 2.0,
            (mount_min.y + mount_max.y) / 2.0,
            mount_min.z,
        );
        let motor_bodies = Solid::read_step(&mut File::open(asset(DRIVE_MOTOR_STEP))?)?;
        Ok(Self {
            mount_bodies,
            motor_bodies,
            mount_anchor,
        })
    }

    pub fn place_mount(&self, origin: DVec3, side: Side) -> Vec<Solid> {
        self.mount_bodies
            .iter()
            .cloned()
            .map(|s| {
                let centered = s
                    .translate(-self.mount_anchor)
                    .rotate_x(PI)
                    .rotate_z(FRAC_PI_2);
                let oriented = match side {
                    Side::Left => centered.mirror(DVec3::ZERO, DVec3::Y),
                    Side::Right => centered,
                };
                oriented.translate(origin)
            })
            .collect()
    }

    pub fn place_motor(&self, origin: DVec3, side: Side) -> Vec<Solid> {
        self.motor_bodies
            .iter()
            .cloned()
            .map(|s| {
                let oriented = match side {
                    Side::Left => s,
                    Side::Right => s.mirror(DVec3::ZERO, DVec3::Y),
                };
                oriented.translate(origin)
            })
            .collect()
    }
}

pub fn drivetrain() -> Result<Vec<Link>, Box<dyn Error>> {
    let motor_mount = MotorMountAssembly::load()?;
    let wheel = WheelAssembly::load()?;

    let mut links: Vec<Link> = Vec::with_capacity(12);
    for corner in Corner::ALL {
        let side = corner.side();
        let mount_origin = placement::mount_origin(corner);
        let motor_origin = placement::motor_origin(corner);
        let wheel_origin = placement::wheel_origin(corner);
        links.push(Link {
            id: corner.mount_link(),
            origin_world: mount_origin,
            solids: motor_mount.place_mount(mount_origin, side),
        });
        links.push(Link {
            id: corner.motor_link(),
            origin_world: motor_origin,
            solids: motor_mount.place_motor(motor_origin, side),
        });
        links.push(Link {
            id: corner.wheel_link(),
            origin_world: wheel_origin,
            solids: wheel.place_wheel(wheel_origin, side),
        });
    }

    Ok(links)
}

pub struct WheelAssembly {
    bodies: Vec<Solid>,
}

impl WheelAssembly {
    pub fn load() -> Result<Self, Box<dyn Error>> {
        let tread_bodies = Solid::read_step(&mut File::open(asset(WHEEL_TREAD_STEP))?)?;
        let [tread_min, tread_max] = combined_bounds(&tread_bodies);
        assert_datum(
            "WHEEL_TREAD_DIAMETER_MM",
            WHEEL_TREAD_DIAMETER_MM,
            tread_max.x - tread_min.x,
        );
        assert_datum(
            "WHEEL_TREAD_WIDTH_MM",
            WHEEL_TREAD_WIDTH_MM,
            tread_max.y - tread_min.y,
        );
        let mut bodies = tread_bodies
            .into_iter()
            .map(|s| s.with_material(Material::Rubber))
            .collect::<Vec<_>>();
        bodies.extend(Solid::read_step(&mut File::open(asset(WHEEL_RIM_STEP))?)?);
        let hub_bodies = Solid::read_step(&mut File::open(asset(WHEEL_HUB_STEP))?)?;
        let [hub_min, _] = combined_bounds(&hub_bodies);
        assert_datum(
            "WHEEL_HUB_INBOARD_FACE_FROM_STEP_ORIGIN_MM",
            WHEEL_HUB_INBOARD_FACE_FROM_STEP_ORIGIN_MM,
            -hub_min.y,
        );
        bodies.extend(hub_bodies);
        Ok(Self { bodies })
    }

    pub fn place_wheel(&self, origin: DVec3, side: Side) -> Vec<Solid> {
        self.bodies
            .iter()
            .cloned()
            .map(|s| {
                let oriented = match side {
                    Side::Left => s,
                    Side::Right => s.mirror(DVec3::ZERO, DVec3::Y),
                };
                oriented.translate(origin)
            })
            .collect()
    }
}

pub fn wheel() -> Result<Vec<Link>, Box<dyn Error>> {
    let wheel = WheelAssembly::load()?;
    Ok(vec![Link {
        id: LinkId::WheelFrontLeft,
        origin_world: DVec3::ZERO,
        solids: wheel.place_wheel(DVec3::ZERO, Side::Left),
    }])
}

pub fn mount_motor_and_wheel() -> Result<Vec<Link>, Box<dyn Error>> {
    let motor_mount = MotorMountAssembly::load()?;
    let wheel = WheelAssembly::load()?;
    let mount_origin = DVec3::ZERO;
    let motor_origin = mount_origin + placement::motor_offset_from_mount(Side::Left);
    let wheel_origin = motor_origin + placement::wheel_offset_from_motor(Side::Left);
    Ok(vec![
        Link {
            id: LinkId::MountFrontLeft,
            origin_world: mount_origin,
            solids: motor_mount.place_mount(mount_origin, Side::Left),
        },
        Link {
            id: LinkId::MotorFrontLeft,
            origin_world: motor_origin,
            solids: motor_mount.place_motor(motor_origin, Side::Left),
        },
        Link {
            id: LinkId::WheelFrontLeft,
            origin_world: wheel_origin,
            solids: wheel.place_wheel(wheel_origin, Side::Left),
        },
    ])
}

pub fn mount_and_motor() -> Result<Vec<Link>, Box<dyn Error>> {
    let motor_mount = MotorMountAssembly::load()?;
    let mount_origin = DVec3::ZERO;
    let motor_origin = mount_origin + placement::motor_offset_from_mount(Side::Left);
    Ok(vec![
        Link {
            id: LinkId::MountFrontLeft,
            origin_world: mount_origin,
            solids: motor_mount.place_mount(mount_origin, Side::Left),
        },
        Link {
            id: LinkId::MotorFrontLeft,
            origin_world: motor_origin,
            solids: motor_mount.place_motor(motor_origin, Side::Left),
        },
    ])
}

pub fn robot() -> Result<Vec<Link>, Box<dyn Error>> {
    let mut chassis_solids: Vec<Solid> = Vec::new();
    chassis_solids.push(time_it!("plank", plank()));
    chassis_solids.extend(time_it!("frame", frame())?);
    chassis_solids.extend(time_it!("gussets", gussets())?);
    chassis_solids.extend(time_it!("rail_end_caps", rail_end_caps())?);
    chassis_solids.extend(time_it!("vertical_posts", vertical_posts())?);
    chassis_solids.extend(time_it!("post_gussets", post_gussets())?);
    chassis_solids.extend(time_it!("post_caps", post_caps())?);
    chassis_solids.extend(time_it!("deck_parts", deck_parts())?);

    let drivetrain_links = time_it!("drivetrain", drivetrain())?;

    let mut links = vec![
        Link {
            id: LinkId::BaseFootprint,
            origin_world: DVec3::new(0.0, 0.0, placement::ground_z()),
            solids: Vec::new(),
        },
        Link {
            id: LinkId::Chassis,
            origin_world: DVec3::ZERO,
            solids: chassis_solids,
        },
    ];
    links.extend(drivetrain_links);
    Ok(links)
}
