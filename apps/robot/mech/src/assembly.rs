use std::{
    error::Error,
    f64::consts::{FRAC_PI_2, PI},
    fs::File,
};

use cadrum::{Boolean, Color, DVec3, Solid};
use crate::{
    datums::{
        MOTOR_MOUNT_WIDTH_MM, WHEEL_HUB_INBOARD_FACE_FROM_STEP_ORIGIN_MM, WHEEL_TREAD_DIAMETER_MM,
        WHEEL_TREAD_WIDTH_MM,
    },
    dimensions::Dimensions,
    parameters::{
        CASTER_MOUNT_BAR_LENGTH_MM, CASTER_MOUNT_BAR_PITCH_MM, CASTER_MOUNT_BAR_WIDTH_MM,
        GUSSET_ARM_LENGTH_MM, GUSSET_ARM_WIDTH_MM, GUSSET_HOLES_PER_ARM, GUSSET_HOLE_DIAMETER_MM,
        GUSSET_HOLE_PITCH_MM, GUSSET_THICKNESS_MM, POST_HEIGHT_MM, POST_INSET_FROM_END_MM,
        POST_LENGTHWISE_BAR_DROP_FROM_TOP_MM, RAIL_CROSS_HEIGHT_MM, RAIL_CROSS_WIDTH_MM,
        RAIL_END_CAP_BOSS_DEPTH_MM, RAIL_END_CAP_BOSS_WALL_MM, RAIL_END_CAP_FLANGE_THICKNESS_MM,
        RAIL_FILLET_RADIUS_MM, RAIL_HOLE_DIAMETER_MM, RAIL_HOLE_SPACING_MM, RAIL_WALL_THICKNESS_MM,
    },
    placement::{self, Corner, Side},
};

use crate::{
    cad_asset,
    material::{Material, WithMaterial},
    time_it, Link, LinkId,
};

const CASTER_TIRE_MIN_DIAMETER_MM: f64 = 250.0;
const OAK_FRONT_WINDOW_MAX_THICKNESS_MM: f64 = 0.65;
const EDGE_COINCIDENCE_EPSILON_MM: f64 = 1e-6;
const CUTTER_OVERSHOOT_MM: f64 = 1.0;
const CAVITY_OVERSHOOT_MM: f64 = 0.5;
const DATUM_TOLERANCE_MM: f64 = 1e-3;

pub const WHEEL_TREAD_STEP: &str = "wheel_tread.step";
pub const WHEEL_RIM_STEP: &str = "wheel_rim.step";
pub const WHEEL_HUB_STEP: &str = "wheel_hub.step";
pub const MOTOR_MOUNT_STEP: &str = "motor_mount.step";
pub const DRIVE_MOTOR_STEP: &str = "drive_motor.step";
pub const CASTER_STEP: &str = "caster.step";
pub const ENCLOSURE_BOX_STEP: &str = "enclosure_box.step";
pub const BALL_HEAD_MOUNT_STEP: &str = "ball_head_mount.step";
pub const E_STOP_BUTTON_STEP: &str = "e_stop_button.step";
pub const CROSSOVER_CONNECTOR_STEP: &str = "crossover_connector.step";
pub const PTQ_1106_FIBERGLASS_ENCLOSURE_BOX_STEP: &str = "ptq_1106_fiberglass_enclosure_box.step";
pub const PRE_DRILLED_1X1_ALUMINUM_BAR_STEP: &str = "pre_drilled_1x1_aluminum_bar.step";
pub const ORBBEC_GEMINI_335L_STEP: &str = "orbbec_gemini_335l.step";
pub const OAK_D_PRO_W_POE_STEP: &str = "oak_d_pro_w_poe.step";

fn box_centered(size: DVec3, center: DVec3) -> Solid {
    Solid::cube(center - size / 2.0, center + size / 2.0)
}

fn hole_row(
    hole_radius: f64,
    cutter_axis: DVec3,
    first_center: DVec3,
    pitch: DVec3,
    hole_count: usize,
) -> impl Iterator<Item = Solid> {
    (0..hole_count).map(move |hole_index| {
        Solid::cylinder(hole_radius, cutter_axis)
            .translate(first_center + hole_index as f64 * pitch)
    })
}

fn subtract_cutters(shape: &Solid, cutters: &[Solid]) -> Result<Solid, cadrum::Error> {
    cutters
        .iter()
        .fold(Boolean::from(shape), |difference, cutter| {
            difference - cutter
        })
        .build()
        .and_then(|solid| solid.clean())
}

fn plank(dimensions: &Dimensions) -> Solid {
    let plank_length = dimensions.frame_length_mm - 2.0 * RAIL_CROSS_WIDTH_MM;
    let plank_width = dimensions.frame_width_mm - 2.0 * RAIL_CROSS_WIDTH_MM;
    let plank_center_z = dimensions.frame_top_z_mm - RAIL_CROSS_HEIGHT_MM / 2.0;
    box_centered(
        DVec3::new(plank_length, plank_width, RAIL_CROSS_HEIGHT_MM),
        DVec3::new(0.0, 0.0, plank_center_z),
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

    let hole_pitch = DVec3::X * RAIL_HOLE_SPACING_MM;
    let mut cutters: Vec<Solid> = Vec::new();
    for y_row in [-wide_face_row_y_offset, wide_face_row_y_offset] {
        cutters.extend(hole_row(
            hole_radius,
            top_bottom_hole_cutter_axis,
            DVec3::new(first_hole_x, y_row, -half_z - CUTTER_OVERSHOOT_MM),
            hole_pitch,
            hole_count,
        ));
    }
    cutters.extend(hole_row(
        hole_radius,
        side_hole_cutter_axis,
        DVec3::new(first_hole_x, -half_y - CUTTER_OVERSHOOT_MM, 0.0),
        hole_pitch,
        hole_count,
    ));

    subtract_cutters(&outer_shell, &cutters)
        .map(|solid| solid.translate(DVec3::Z * (-RAIL_CROSS_HEIGHT_MM / 2.0)))
}

fn frame(dimensions: &Dimensions) -> Result<Vec<Solid>, cadrum::Error> {
    let side_rail_center_y = dimensions.frame_width_mm / 2.0 - RAIL_CROSS_WIDTH_MM / 2.0;
    let front_x = dimensions.frame_length_mm / 2.0 - RAIL_CROSS_WIDTH_MM / 2.0;
    let rear_x = -dimensions.frame_length_mm / 2.0 + RAIL_CROSS_WIDTH_MM / 2.0;
    let cross_length = dimensions.frame_width_mm - 2.0 * RAIL_CROSS_WIDTH_MM;

    let side_rail = perforated_rail(dimensions.frame_length_mm)?;
    let cross_rail = perforated_rail(cross_length)?.rotate_z(FRAC_PI_2);

    Ok([
        side_rail.clone().translate(DVec3::new(
            0.0,
            side_rail_center_y,
            dimensions.frame_top_z_mm,
        )),
        side_rail.translate(DVec3::new(
            0.0,
            -side_rail_center_y,
            dimensions.frame_top_z_mm,
        )),
        cross_rail
            .clone()
            .translate(DVec3::new(front_x, 0.0, dimensions.frame_top_z_mm)),
        cross_rail.translate(DVec3::new(rear_x, 0.0, dimensions.frame_top_z_mm)),
    ]
    .into_iter()
    .map(|rail| rail.with_material(Material::Aluminum))
    .collect())
}

fn vertical_posts(dimensions: &Dimensions) -> Result<Vec<Solid>, cadrum::Error> {
    let post_template = perforated_rail(POST_HEIGHT_MM)?
        .translate(DVec3::Z * (RAIL_CROSS_HEIGHT_MM / 2.0))
        .rotate_y(-FRAC_PI_2);
    let post_x_extent = dimensions.frame_length_mm / 2.0 - POST_INSET_FROM_END_MM;
    let side_rail_center_y = dimensions.frame_width_mm / 2.0 - RAIL_CROSS_WIDTH_MM / 2.0;
    let post_center_z = dimensions.frame_top_z_mm + POST_HEIGHT_MM / 2.0;

    let mut parts = Vec::with_capacity(4);
    for post_x in [-post_x_extent, post_x_extent] {
        for post_y_sign in [1.0, -1.0] {
            parts.push(
                post_template
                    .clone()
                    .translate(DVec3::new(
                        post_x,
                        post_y_sign * side_rail_center_y,
                        post_center_z,
                    ))
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

    let mut cutters: Vec<Solid> = hole_row(
        hole_radius,
        cutter_axis,
        DVec3::new(0.0, cutter_y_start, 0.0),
        DVec3::Z * GUSSET_HOLE_PITCH_MM,
        GUSSET_HOLES_PER_ARM,
    )
    .collect();
    cutters.extend(hole_row(
        hole_radius,
        cutter_axis,
        DVec3::new(
            GUSSET_HOLE_PITCH_MM,
            cutter_y_start,
            -RAIL_CROSS_HEIGHT_MM / 2.0,
        ),
        DVec3::X * GUSSET_HOLE_PITCH_MM,
        GUSSET_HOLES_PER_ARM - 1,
    ));

    subtract_cutters(&l_shape, &cutters)
}

fn post_gussets(dimensions: &Dimensions) -> Result<Vec<Solid>, Box<dyn Error>> {
    let gusset_template = outer_face_gusset()?;

    let post_x_extent = dimensions.frame_length_mm / 2.0 - POST_INSET_FROM_END_MM;
    let side_rail_center_y = dimensions.frame_width_mm / 2.0 - RAIL_CROSS_WIDTH_MM / 2.0;

    let mut gussets = Vec::with_capacity(8);
    for post_x_sign in [1.0, -1.0] {
        for post_y_sign in [1.0, -1.0] {
            let post_x = post_x_sign * post_x_extent;
            let post_outer_face_y =
                post_y_sign * side_rail_center_y + post_y_sign * (RAIL_CROSS_WIDTH_MM / 2.0);
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
                        .translate(DVec3::new(
                            post_x,
                            post_outer_face_y,
                            dimensions.frame_top_z_mm,
                        ))
                        .with_material(Material::Steel),
                );
            }
        }
    }
    Ok(gussets)
}

const CROSSOVER_CONNECTOR_CLEARANCE_FROM_POST_FACE_MM: f64 = 76.2;
const CROSSOVER_CONNECTOR_LENGTH_MM: f64 = 127.0;
const CROSSOVER_CONNECTOR_PLATE_THICKNESS_MM: f64 = 12.7;
const CROSSOVER_CONNECTOR_PLATE_MIN_LENGTH_MM: f64 = 100.0;
const CROSSOVER_BAR_OVERHANG_MM: f64 = 76.2;

fn crossover_connector_center_x(dimensions: &Dimensions) -> f64 {
    let post_x_extent = dimensions.frame_length_mm / 2.0 - POST_INSET_FROM_END_MM;
    let post_inner_face_x = post_x_extent - RAIL_CROSS_HEIGHT_MM / 2.0;
    post_inner_face_x
        - CROSSOVER_CONNECTOR_CLEARANCE_FROM_POST_FACE_MM
        - CROSSOVER_CONNECTOR_LENGTH_MM / 2.0
}

fn crossover_connectors(dimensions: &Dimensions) -> Result<Vec<Solid>, Box<dyn Error>> {
    let imported = Solid::read_step(&mut File::open(cad_asset(CROSSOVER_CONNECTOR_STEP))?)?;
    let oriented: Vec<Solid> = imported
        .into_iter()
        .map(|solid| {
            let solid = solid.rotate_x(FRAC_PI_2);
            let [min, max] = solid.bounding_box();
            let material = if max.x - min.x >= CROSSOVER_CONNECTOR_PLATE_MIN_LENGTH_MM {
                Material::Steel
            } else {
                Material::Aluminum
            };
            solid.with_material(material)
        })
        .collect();

    let connector_center_x = crossover_connector_center_x(dimensions);
    let side_rail_center_y = dimensions.frame_width_mm / 2.0 - RAIL_CROSS_WIDTH_MM / 2.0;
    let post_lengthwise_bar_top_z =
        dimensions.frame_top_z_mm + POST_HEIGHT_MM - POST_LENGTHWISE_BAR_DROP_FROM_TOP_MM;

    let mut parts = Vec::with_capacity(oriented.len() * 4);
    for connector_x_sign in [1.0, -1.0] {
        for bar_y_sign in [1.0, -1.0] {
            let connector_position = DVec3::new(
                connector_x_sign * connector_center_x,
                bar_y_sign * side_rail_center_y,
                post_lengthwise_bar_top_z,
            );
            parts.extend(
                oriented
                    .iter()
                    .cloned()
                    .map(|solid| solid.translate(connector_position)),
            );
        }
    }
    Ok(parts)
}

fn crossover_bars(dimensions: &Dimensions) -> Result<Vec<Solid>, Box<dyn Error>> {
    let bar_length = dimensions.frame_width_mm + 2.0 * CROSSOVER_BAR_OVERHANG_MM;
    let plate_top_z = dimensions.frame_top_z_mm + POST_HEIGHT_MM
        - POST_LENGTHWISE_BAR_DROP_FROM_TOP_MM
        + CROSSOVER_CONNECTOR_PLATE_THICKNESS_MM;
    let bar_template = perforated_rail(bar_length)?.rotate_z(FRAC_PI_2);
    let connector_center_x = crossover_connector_center_x(dimensions);

    Ok([1.0, -1.0]
        .into_iter()
        .map(|bar_x_sign| {
            bar_template
                .clone()
                .translate(DVec3::new(
                    bar_x_sign * connector_center_x,
                    0.0,
                    plate_top_z + RAIL_CROSS_HEIGHT_MM,
                ))
                .with_material(Material::Aluminum)
        })
        .collect())
}

fn tee_gusset() -> Result<Solid, cadrum::Error> {
    let half_width = GUSSET_ARM_WIDTH_MM / 2.0;
    let vertical_arm = Solid::cube(
        DVec3::new(
            -half_width,
            0.0,
            -(RAIL_CROSS_HEIGHT_MM + GUSSET_ARM_LENGTH_MM),
        ),
        DVec3::new(half_width, GUSSET_THICKNESS_MM, GUSSET_ARM_LENGTH_MM),
    );
    let horizontal_arm = Solid::cube(
        DVec3::new(-half_width, 0.0, -RAIL_CROSS_HEIGHT_MM),
        DVec3::new(GUSSET_ARM_LENGTH_MM, GUSSET_THICKNESS_MM, 0.0),
    );
    let tee_shape = (&vertical_arm + &horizontal_arm).build()?;

    let hole_radius = GUSSET_HOLE_DIAMETER_MM / 2.0;
    let cutter_axis = DVec3::Y * (GUSSET_THICKNESS_MM + 2.0 * CUTTER_OVERSHOOT_MM);
    let cutter_y_start = -CUTTER_OVERSHOOT_MM;

    let mut cutters: Vec<Solid> = hole_row(
        hole_radius,
        cutter_axis,
        DVec3::new(0.0, cutter_y_start, 0.0),
        DVec3::Z * GUSSET_HOLE_PITCH_MM,
        GUSSET_HOLES_PER_ARM,
    )
    .collect();
    cutters.extend(hole_row(
        hole_radius,
        cutter_axis,
        DVec3::new(
            0.0,
            cutter_y_start,
            -RAIL_CROSS_HEIGHT_MM - GUSSET_HOLE_PITCH_MM,
        ),
        DVec3::Z * -GUSSET_HOLE_PITCH_MM,
        GUSSET_HOLES_PER_ARM - 1,
    ));
    cutters.extend(hole_row(
        hole_radius,
        cutter_axis,
        DVec3::new(
            GUSSET_HOLE_PITCH_MM,
            cutter_y_start,
            -RAIL_CROSS_HEIGHT_MM / 2.0,
        ),
        DVec3::X * GUSSET_HOLE_PITCH_MM,
        GUSSET_HOLES_PER_ARM - 1,
    ));

    subtract_cutters(&tee_shape, &cutters)
}

fn post_lengthwise_bars(dimensions: &Dimensions) -> Result<Vec<Solid>, Box<dyn Error>> {
    let post_x_extent = dimensions.frame_length_mm / 2.0 - POST_INSET_FROM_END_MM;
    let side_rail_center_y = dimensions.frame_width_mm / 2.0 - RAIL_CROSS_WIDTH_MM / 2.0;
    let bar_length = 2.0 * post_x_extent - RAIL_CROSS_HEIGHT_MM;
    let post_lengthwise_bar_top_z =
        dimensions.frame_top_z_mm + POST_HEIGHT_MM - POST_LENGTHWISE_BAR_DROP_FROM_TOP_MM;

    let bar_template = perforated_rail(bar_length)?;
    let gusset_template = tee_gusset()?;

    let mut parts = Vec::new();
    for bar_y_sign in [1.0, -1.0] {
        let bar_y = bar_y_sign * side_rail_center_y;
        parts.push(
            bar_template
                .clone()
                .translate(DVec3::new(0.0, bar_y, post_lengthwise_bar_top_z))
                .with_material(Material::Aluminum),
        );
        for post_x_sign in [1.0, -1.0] {
            for face_y_sign in [1.0, -1.0] {
                let mut gusset = gusset_template.clone();
                if post_x_sign > 0.0 {
                    gusset = gusset.mirror(DVec3::ZERO, DVec3::X);
                }
                if face_y_sign < 0.0 {
                    gusset = gusset.mirror(DVec3::ZERO, DVec3::Y);
                }
                let gusset_face_y = bar_y + face_y_sign * (RAIL_CROSS_WIDTH_MM / 2.0);
                parts.push(
                    gusset
                        .translate(DVec3::new(
                            post_x_sign * post_x_extent,
                            gusset_face_y,
                            post_lengthwise_bar_top_z,
                        ))
                        .with_material(Material::Steel),
                );
            }
        }
    }
    Ok(parts)
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

    let mut cutters: Vec<Solid> = hole_row(
        hole_radius,
        hole_axis,
        DVec3::new(0.0, 0.0, hole_z_bottom),
        DVec3::X * GUSSET_HOLE_PITCH_MM,
        GUSSET_HOLES_PER_ARM,
    )
    .collect();
    cutters.extend(hole_row(
        hole_radius,
        hole_axis,
        DVec3::new(0.0, -GUSSET_HOLE_PITCH_MM, hole_z_bottom),
        DVec3::Y * -GUSSET_HOLE_PITCH_MM,
        GUSSET_HOLES_PER_ARM - 1,
    ));

    subtract_cutters(&l_shape, &cutters)
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

fn rail_end_caps(dimensions: &Dimensions) -> Result<Vec<Solid>, cadrum::Error> {
    let end_cap_template = rail_end_cap()?.with_material(Material::BlackPlastic);

    let rail_center_z = dimensions.frame_top_z_mm - RAIL_CROSS_HEIGHT_MM / 2.0;
    let side_rail_center_y = dimensions.frame_width_mm / 2.0 - RAIL_CROSS_WIDTH_MM / 2.0;
    let rear_x_outer = -dimensions.frame_length_mm / 2.0;
    let front_x_outer = dimensions.frame_length_mm / 2.0;

    let placements = [
        (0.0, rear_x_outer, side_rail_center_y),
        (PI, front_x_outer, side_rail_center_y),
        (0.0, rear_x_outer, -side_rail_center_y),
        (PI, front_x_outer, -side_rail_center_y),
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

fn post_caps(dimensions: &Dimensions) -> Result<Vec<Solid>, cadrum::Error> {
    let cap_template = rail_end_cap()?
        .rotate_y(FRAC_PI_2)
        .with_material(Material::BlackPlastic);

    let post_x_extent = dimensions.frame_length_mm / 2.0 - POST_INSET_FROM_END_MM;
    let side_rail_center_y = dimensions.frame_width_mm / 2.0 - RAIL_CROSS_WIDTH_MM / 2.0;
    let post_top_z = dimensions.frame_top_z_mm + POST_HEIGHT_MM;

    let mut caps = Vec::with_capacity(4);
    for post_x in [-post_x_extent, post_x_extent] {
        for post_y_sign in [1.0, -1.0] {
            caps.push(cap_template.clone().translate(DVec3::new(
                post_x,
                post_y_sign * side_rail_center_y,
                post_top_z,
            )));
        }
    }
    Ok(caps)
}

fn gussets(dimensions: &Dimensions) -> Result<Vec<Solid>, Box<dyn Error>> {
    let gusset_template = corner_gusset()?.with_material(Material::Steel);

    let rear_outer_x = -dimensions.frame_length_mm / 2.0;
    let front_outer_x = dimensions.frame_length_mm / 2.0;
    let outer_y = dimensions.frame_width_mm / 2.0;
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
                .translate(DVec3::new(x, y, dimensions.frame_top_z_mm))
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
    let imported_solids = Solid::read_step(&mut File::open(cad_asset(asset_name))?)?;
    let oriented: Vec<Solid> = imported_solids.into_iter().map(orient).collect();
    let [min, max] = combined_bounds(&oriented);
    let anchor_z = match z_anchor {
        ZAnchor::Bottom => min.z,
        ZAnchor::Top => max.z,
    };
    let anchor = min.midpoint(max).with_z(anchor_z);
    Ok(oriented
        .into_iter()
        .map(|solid| solid.translate(position - anchor))
        .collect())
}

const E_STOP_MUSHROOM_MIN_X_MM: f64 = 513.0;
const E_STOP_MUSHROOM_RED: Color = Color {
    r: 0.8,
    g: 0.05,
    b: 0.05,
};
const E_STOP_BASE_BLACK: Color = Color {
    r: 0.06,
    g: 0.06,
    b: 0.06,
};

fn recolored_e_stop_button() -> Result<Vec<Solid>, Box<dyn Error>> {
    let imported = Solid::read_step(&mut File::open(cad_asset(E_STOP_BUTTON_STEP))?)?;
    Ok(imported
        .into_iter()
        .map(|mut solid| {
            let face_min_x: Vec<(u64, f64)> = solid
                .iter_face()
                .map(|face| {
                    let min_x = face
                        .iter_edge()
                        .flat_map(|edge| [edge.start_point().x, edge.end_point().x])
                        .fold(f64::INFINITY, f64::min);
                    (face.id(), min_x)
                })
                .collect();
            let colormap = solid.colormap_mut();
            for (face_id, min_x) in face_min_x {
                colormap
                    .entry(face_id)
                    .or_insert(if min_x >= E_STOP_MUSHROOM_MIN_X_MM {
                        E_STOP_MUSHROOM_RED
                    } else {
                        E_STOP_BASE_BLACK
                    });
            }
            solid
        })
        .collect())
}

fn e_stop_buttons(dimensions: &Dimensions) -> Result<Vec<Solid>, Box<dyn Error>> {
    let template = recolored_e_stop_button()?;
    let post_x_extent = dimensions.frame_length_mm / 2.0 - POST_INSET_FROM_END_MM;
    let side_rail_center_y = dimensions.frame_width_mm / 2.0 - RAIL_CROSS_WIDTH_MM / 2.0;
    let post_face_from_center = RAIL_CROSS_HEIGHT_MM / 2.0;
    let post_top_z = dimensions.frame_top_z_mm + POST_HEIGHT_MM;

    let mut parts = Vec::with_capacity(template.len() * 2);
    for (is_facing_forward, post_x, post_y) in [
        (true, post_x_extent, -side_rail_center_y),
        (false, -post_x_extent, side_rail_center_y),
    ] {
        let oriented: Vec<Solid> = template
            .iter()
            .cloned()
            .map(|solid| {
                if is_facing_forward {
                    solid
                } else {
                    solid.rotate_z(PI)
                }
            })
            .collect();
        let [min, max] = combined_bounds(&oriented);
        let mounting_face_x = if is_facing_forward {
            post_x + post_face_from_center - min.x
        } else {
            post_x - post_face_from_center - max.x
        };
        let offset = DVec3::new(
            mounting_face_x,
            post_y - (min.y + max.y) / 2.0,
            post_top_z - max.z,
        );
        parts.extend(oriented.into_iter().map(|solid| solid.translate(offset)));
    }
    Ok(parts)
}

const SIDE_ENCLOSURE_TOP_ABOVE_BAR_MM: f64 = 76.2;

fn side_mounted_enclosure(
    asset_name: &str,
    side: Side,
    orient: impl Fn(Solid) -> Solid,
    dimensions: &Dimensions,
) -> Result<Vec<Solid>, Box<dyn Error>> {
    let imported = Solid::read_step(&mut File::open(cad_asset(asset_name))?)?;
    let oriented: Vec<Solid> = imported
        .into_iter()
        .map(|solid| orient(solid).with_material(Material::GrayPlastic))
        .collect();
    let [min, max] = combined_bounds(&oriented);
    let side_face_y = dimensions.frame_width_mm / 2.0;
    let post_lengthwise_bar_top_z =
        dimensions.frame_top_z_mm + POST_HEIGHT_MM - POST_LENGTHWISE_BAR_DROP_FROM_TOP_MM;
    let offset = DVec3::new(
        -(min.x + max.x) / 2.0,
        match side {
            Side::Left => side_face_y - min.y,
            Side::Right => -side_face_y - max.y,
        },
        post_lengthwise_bar_top_z + SIDE_ENCLOSURE_TOP_ABOVE_BAR_MM - max.z,
    );
    Ok(oriented
        .into_iter()
        .map(|solid| solid.translate(offset))
        .collect())
}

const BALL_HEAD_MOUNT_CENTER_DROP_FROM_POST_TOP_MM: f64 = 38.1;

fn orbbec_gemini_335l_on_ball_head_mount(
    dimensions: &Dimensions,
) -> Result<Vec<Solid>, Box<dyn Error>> {
    let imported = Solid::read_step(&mut File::open(cad_asset(BALL_HEAD_MOUNT_STEP))?)?;
    let oriented: Vec<Solid> = imported
        .into_iter()
        .map(|solid| {
            solid
                .rotate_y(FRAC_PI_2)
                .with_material(Material::BlackPlastic)
        })
        .collect();
    let [mount_min, mount_max] = combined_bounds(&oriented);

    let post_x_extent = dimensions.frame_length_mm / 2.0 - POST_INSET_FROM_END_MM;
    let post_front_face_x = post_x_extent + RAIL_CROSS_HEIGHT_MM / 2.0;
    let side_rail_center_y = dimensions.frame_width_mm / 2.0 - RAIL_CROSS_WIDTH_MM / 2.0;
    let post_top_z = dimensions.frame_top_z_mm + POST_HEIGHT_MM;
    let mount_offset = DVec3::new(
        post_front_face_x - mount_min.x,
        side_rail_center_y - (mount_min.y + mount_max.y) / 2.0,
        post_top_z
            - BALL_HEAD_MOUNT_CENTER_DROP_FROM_POST_TOP_MM
            - (mount_min.z + mount_max.z) / 2.0,
    );
    let mut parts: Vec<Solid> = oriented
        .into_iter()
        .map(|solid| solid.translate(mount_offset))
        .collect();

    let camera_imported = Solid::read_step(&mut File::open(cad_asset(ORBBEC_GEMINI_335L_STEP))?)?;
    let camera_oriented: Vec<Solid> = camera_imported
        .into_iter()
        .map(|solid| solid.rotate_z(-FRAC_PI_2).rotate_y(FRAC_PI_2))
        .collect();
    let [camera_min, camera_max] = combined_bounds(&camera_oriented);
    let mount_front_x = mount_max.x + mount_offset.x;
    let mount_center_z = (mount_min.z + mount_max.z) / 2.0 + mount_offset.z;
    let camera_offset = DVec3::new(
        mount_front_x - camera_min.x,
        side_rail_center_y - (camera_min.y + camera_max.y) / 2.0,
        mount_center_z - (camera_min.z + camera_max.z) / 2.0,
    );
    parts.extend(
        camera_oriented
            .into_iter()
            .map(|solid| solid.translate(camera_offset)),
    );
    Ok(parts)
}

fn enclosure_box(dimensions: &Dimensions) -> Result<Vec<Solid>, Box<dyn Error>> {
    Ok(place_component(
        ENCLOSURE_BOX_STEP,
        DVec3::new(0.0, 0.0, dimensions.frame_top_z_mm),
        ZAnchor::Bottom,
        |solid| solid.rotate_x(PI).rotate_z(FRAC_PI_2),
    )?
    .into_iter()
    .map(|solid| solid.with_material(Material::GrayPlastic))
    .collect())
}

fn oak_d_pro_w_poe_on_ball_head_mount(
    dimensions: &Dimensions,
) -> Result<Vec<Solid>, Box<dyn Error>> {
    let front_rail_center_x = dimensions.frame_length_mm / 2.0 - RAIL_CROSS_WIDTH_MM / 2.0;
    let mut parts: Vec<Solid> = place_component(
        BALL_HEAD_MOUNT_STEP,
        DVec3::new(front_rail_center_x, 0.0, dimensions.frame_top_z_mm),
        ZAnchor::Bottom,
        |solid| solid,
    )?
    .into_iter()
    .map(|solid| solid.with_material(Material::BlackPlastic))
    .collect();
    let [_, mount_top] = combined_bounds(&parts);
    parts.extend(
        place_component(
            OAK_D_PRO_W_POE_STEP,
            DVec3::new(front_rail_center_x, 0.0, mount_top.z),
            ZAnchor::Bottom,
            |solid| solid.rotate_z(-FRAC_PI_2).rotate_y(FRAC_PI_2),
        )?
        .into_iter()
        .map(|solid| {
            let [min, max] = solid.bounding_box();
            let thinnest_extent = (max - min).min_element();
            let material = if thinnest_extent < OAK_FRONT_WINDOW_MAX_THICKNESS_MM {
                Material::BlackPlastic
            } else {
                Material::Steel
            };
            solid.with_material(material)
        }),
    );
    Ok(parts)
}

fn caster_mount_bars(dimensions: &Dimensions) -> Result<Vec<Solid>, Box<dyn Error>> {
    let imported = Solid::read_step(&mut File::open(cad_asset(PRE_DRILLED_1X1_ALUMINUM_BAR_STEP))?)?;
    let across_bar_span = 2.0 * CASTER_MOUNT_BAR_PITCH_MM + CASTER_MOUNT_BAR_WIDTH_MM;
    let trim_half_section = CASTER_MOUNT_BAR_WIDTH_MM / 2.0 + CUTTER_OVERSHOOT_MM;
    let along_bar_keep = Solid::cube(
        DVec3::new(
            -across_bar_span / 2.0,
            -trim_half_section,
            -trim_half_section,
        ),
        DVec3::new(across_bar_span / 2.0, trim_half_section, trim_half_section),
    );

    let along_frame: Vec<Solid> = imported
        .iter()
        .map(|solid| {
            (solid * &along_bar_keep)
                .build()
                .and_then(|solid| solid.clean())
                .map(|solid| solid.with_material(Material::Aluminum))
        })
        .collect::<Result<_, _>>()?;
    let across_frame: Vec<Solid> = imported
        .into_iter()
        .map(|solid| solid.rotate_z(FRAC_PI_2).with_material(Material::Aluminum))
        .collect();

    let middle_bar_center_x = Corner::FrontLeft.axle_x(dimensions);
    let rail_inner_face_y = dimensions.frame_width_mm / 2.0 - RAIL_CROSS_WIDTH_MM;
    let across_bar_center_y = rail_inner_face_y + CASTER_MOUNT_BAR_LENGTH_MM / 2.0;
    let across_bar_center_z = dimensions.frame_top_z_mm + CASTER_MOUNT_BAR_WIDTH_MM / 2.0;
    let along_bar_center_y =
        rail_inner_face_y + CASTER_MOUNT_BAR_LENGTH_MM - CASTER_MOUNT_BAR_WIDTH_MM / 2.0;
    let along_bar_center_z = dimensions.frame_top_z_mm - CASTER_MOUNT_BAR_WIDTH_MM / 2.0;

    let mut parts = Vec::with_capacity((across_frame.len() * 3 + along_frame.len()) * 2);
    for corner in Corner::FRONT {
        let outboard = placement::outboard_sign(corner.side());
        for bar_index in [-1.0, 0.0, 1.0] {
            let across_bar_position = DVec3::new(
                middle_bar_center_x + bar_index * CASTER_MOUNT_BAR_PITCH_MM,
                outboard * across_bar_center_y,
                across_bar_center_z,
            );
            parts.extend(
                across_frame
                    .iter()
                    .cloned()
                    .map(|solid| solid.translate(across_bar_position)),
            );
        }
        let along_bar_position = DVec3::new(
            middle_bar_center_x,
            outboard * along_bar_center_y,
            along_bar_center_z,
        );
        parts.extend(
            along_frame
                .iter()
                .cloned()
                .map(|solid| solid.translate(along_bar_position)),
        );
    }
    Ok(parts)
}

fn casters(dimensions: &Dimensions) -> Result<Vec<Solid>, Box<dyn Error>> {
    let imported = Solid::read_step(&mut File::open(cad_asset(CASTER_STEP))?)?;
    let oriented: Vec<Solid> = imported
        .into_iter()
        .map(|solid| {
            let solid = solid.rotate_x(PI).rotate_z(-FRAC_PI_2);
            let [min, max] = solid.bounding_box();
            let material = if max.z - min.z > CASTER_TIRE_MIN_DIAMETER_MM {
                Material::Rubber
            } else {
                Material::Steel
            };
            solid.with_material(material)
        })
        .collect();
    let [_, overall_max] = combined_bounds(&oriented);
    let mounting_plate = oriented
        .iter()
        .max_by(|left, right| {
            let left_top = left.bounding_box()[1].z;
            let right_top = right.bounding_box()[1].z;
            left_top.total_cmp(&right_top)
        })
        .expect("caster step contains at least one solid");
    let [plate_min, plate_max] = mounting_plate.bounding_box();
    let caster_pivot = plate_min.midpoint(plate_max).with_z(overall_max.z);

    let plate_top_z = dimensions.frame_top_z_mm;
    let bay_center_y = placement::caster_bay_center_y(dimensions);
    let mut parts = Vec::with_capacity(oriented.len() * 2);
    for corner in Corner::FRONT {
        let caster_position = DVec3::new(
            corner.axle_x(dimensions),
            placement::outboard_sign(corner.side()) * bay_center_y,
            plate_top_z,
        );
        parts.extend(
            oriented
                .iter()
                .cloned()
                .map(|solid| solid.translate(caster_position - caster_pivot)),
        );
    }
    Ok(parts)
}

fn assert_datum(name: &str, declared: f64, measured: f64) {
    assert!(
        (declared - measured).abs() < DATUM_TOLERANCE_MM,
        "datum {name}: declared {declared}, measured {measured} — update mech/src/datums.rs"
    );
}

pub struct MotorMountAssembly {
    mount_bodies: Vec<Solid>,
    motor_bodies: Vec<Solid>,
    mount_anchor: DVec3,
}

impl MotorMountAssembly {
    pub fn load() -> Result<Self, Box<dyn Error>> {
        let mount_bodies = Solid::read_step(&mut File::open(cad_asset(MOTOR_MOUNT_STEP))?)?
            .into_iter()
            .map(|solid| solid.with_material(Material::AnodizedAluminum))
            .collect::<Vec<_>>();
        let [mount_min, mount_max] = combined_bounds(&mount_bodies);
        assert_datum(
            "MOTOR_MOUNT_WIDTH_MM",
            MOTOR_MOUNT_WIDTH_MM,
            mount_max.x - mount_min.x,
        );
        let mount_anchor = mount_min.midpoint(mount_max).with_z(mount_min.z);
        let motor_bodies = Solid::read_step(&mut File::open(cad_asset(DRIVE_MOTOR_STEP))?)?;
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
            .map(|solid| {
                let centered = solid
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
            .map(|solid| {
                let oriented = match side {
                    Side::Left => solid,
                    Side::Right => solid.mirror(DVec3::ZERO, DVec3::Y),
                };
                oriented.translate(origin)
            })
            .collect()
    }
}

pub fn drivetrain(dimensions: &Dimensions) -> Result<Vec<Link>, Box<dyn Error>> {
    let motor_mount = MotorMountAssembly::load()?;
    let wheel = WheelAssembly::load()?;

    let mut links: Vec<Link> = Vec::with_capacity(6);
    for corner in Corner::REAR {
        let side = corner.side();
        let mount_origin = placement::mount_origin(corner, dimensions);
        let motor_origin = placement::motor_origin(corner, dimensions);
        let wheel_origin = placement::wheel_origin(corner, dimensions);
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
        let tread_bodies = Solid::read_step(&mut File::open(cad_asset(WHEEL_TREAD_STEP))?)?;
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
            .map(|solid| solid.with_material(Material::Rubber))
            .collect::<Vec<_>>();
        bodies.extend(Solid::read_step(&mut File::open(cad_asset(WHEEL_RIM_STEP))?)?);
        let hub_bodies = Solid::read_step(&mut File::open(cad_asset(WHEEL_HUB_STEP))?)?;
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
            .map(|solid| {
                let oriented = match side {
                    Side::Left => solid.mirror(DVec3::ZERO, DVec3::X),
                    Side::Right => solid.rotate_z(PI),
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

pub fn robot(dimensions: &Dimensions) -> Result<Vec<Link>, Box<dyn Error>> {
    let mut chassis_solids: Vec<Solid> = Vec::new();
    chassis_solids.extend(time_it!("frame", frame(dimensions))?);
    chassis_solids.extend(time_it!("gussets", gussets(dimensions))?);
    chassis_solids.extend(time_it!("rail_end_caps", rail_end_caps(dimensions))?);
    chassis_solids.extend(time_it!("casters", casters(dimensions))?);
    chassis_solids.extend(time_it!(
        "caster_mount_bars",
        caster_mount_bars(dimensions)
    )?);
    if dimensions.has_deck_equipment {
        chassis_solids.extend(time_it!("vertical_posts", vertical_posts(dimensions))?);
        chassis_solids.extend(time_it!("post_gussets", post_gussets(dimensions))?);
        chassis_solids.extend(time_it!("post_caps", post_caps(dimensions))?);
        chassis_solids.extend(time_it!(
            "post_lengthwise_bars",
            post_lengthwise_bars(dimensions)
        )?);
        chassis_solids.extend(time_it!(
            "crossover_connectors",
            crossover_connectors(dimensions)
        )?);
        chassis_solids.extend(time_it!("crossover_bars", crossover_bars(dimensions))?);
        chassis_solids.extend(time_it!(
            "orbbec_gemini_335l_on_ball_head_mount",
            orbbec_gemini_335l_on_ball_head_mount(dimensions)
        )?);
        chassis_solids.extend(time_it!(
            "enclosure_box_on_left_bar",
            side_mounted_enclosure(
                ENCLOSURE_BOX_STEP,
                Side::Left,
                |solid| solid.rotate_x(FRAC_PI_2),
                dimensions,
            )
        )?);
        chassis_solids.extend(time_it!(
            "ptq_1106_fiberglass_enclosure_box_on_right_bar",
            side_mounted_enclosure(
                PTQ_1106_FIBERGLASS_ENCLOSURE_BOX_STEP,
                Side::Right,
                |solid| solid.rotate_x(FRAC_PI_2).rotate_z(PI),
                dimensions,
            )
        )?);
        chassis_solids.extend(time_it!("e_stop_buttons", e_stop_buttons(dimensions))?);
    } else {
        chassis_solids.push(time_it!("plank", plank(dimensions)));
        chassis_solids.extend(time_it!("enclosure_box", enclosure_box(dimensions))?);
        chassis_solids.extend(time_it!(
            "oak_d_pro_w_poe_on_ball_head_mount",
            oak_d_pro_w_poe_on_ball_head_mount(dimensions)
        )?);
    }

    let drivetrain_links = time_it!("drivetrain", drivetrain(dimensions))?;

    let mut links = vec![
        Link {
            id: LinkId::BaseFootprint,
            origin_world: DVec3::new(0.0, 0.0, placement::ground_z(dimensions)),
            solids: Vec::new(),
        },
        Link {
            id: LinkId::CasterFrontLeft,
            origin_world: placement::caster_wheel_center(Corner::FrontLeft, dimensions),
            solids: Vec::new(),
        },
        Link {
            id: LinkId::CasterFrontRight,
            origin_world: placement::caster_wheel_center(Corner::FrontRight, dimensions),
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
