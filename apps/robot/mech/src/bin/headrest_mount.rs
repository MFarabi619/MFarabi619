use std::{error::Error, fs::File};

use cadrum::{DVec3, Solid};
use robot_description::{
    assembly::{box_centered, hole_row, subtract_cutters},
    export::write_solids_glb,
    robot_root,
};

const POLE_CENTER_SPACING_MM: f64 = 203.2;
const POLE_DIAMETER_MM: f64 = 19.05;
const BORE_CLEARANCE_MM: f64 = 0.05;
const BOLT_HOLE_DIAMETER_MM: f64 = 6.6;
const DECK_BOLT_ROW_PITCH_MM: f64 = 139.7;
const DECK_BOLT_COLUMN_PITCH_MM: f64 = 87.63;

const SOCKET_OUTER_WIDTH_MM: f64 = 30.0;
const POLE_BORE_MM: f64 = POLE_DIAMETER_MM + BORE_CLEARANCE_MM;
const SOCKET_LENGTH_MM: f64 = 125.0;
const FLANGE_THICKNESS_MM: f64 = 6.0;
const FLANGE_LENGTH_MM: f64 = 165.0;
const CUTTER_OVERSHOOT_MM: f64 = 1.0;

const FLANGE_WIDTH_MM: f64 = POLE_CENTER_SPACING_MM + SOCKET_OUTER_WIDTH_MM;
const SOCKET_CENTER_Z_MM: f64 = FLANGE_THICKNESS_MM + SOCKET_OUTER_WIDTH_MM / 2.0;

fn socket_tube(center_x: f64) -> (Solid, Solid) {
    let tube = box_centered(
        DVec3::new(SOCKET_OUTER_WIDTH_MM, SOCKET_LENGTH_MM, SOCKET_OUTER_WIDTH_MM),
        DVec3::new(center_x, 0.0, SOCKET_CENTER_Z_MM),
    );
    let cutter = box_centered(
        DVec3::new(
            POLE_BORE_MM,
            SOCKET_LENGTH_MM + 2.0 * CUTTER_OVERSHOOT_MM,
            POLE_BORE_MM,
        ),
        DVec3::new(center_x, 0.0, SOCKET_CENTER_Z_MM),
    );
    (tube, cutter)
}

fn main() -> Result<(), Box<dyn Error>> {
    let flange = box_centered(
        DVec3::new(FLANGE_WIDTH_MM, FLANGE_LENGTH_MM, FLANGE_THICKNESS_MM),
        DVec3::new(0.0, 0.0, FLANGE_THICKNESS_MM / 2.0),
    );
    let socket_center_x = POLE_CENTER_SPACING_MM / 2.0;
    let (left_tube, left_cutter) = socket_tube(-socket_center_x);
    let (right_tube, right_cutter) = socket_tube(socket_center_x);
    let bolt_cutter_height =
        DVec3::new(0.0, 0.0, FLANGE_THICKNESS_MM + 2.0 * CUTTER_OVERSHOOT_MM);
    let cutters: Vec<Solid> = [-1.0, 1.0]
        .into_iter()
        .flat_map(|row_sign: f64| {
            hole_row(
                BOLT_HOLE_DIAMETER_MM / 2.0,
                bolt_cutter_height,
                DVec3::new(
                    -DECK_BOLT_COLUMN_PITCH_MM,
                    row_sign * DECK_BOLT_ROW_PITCH_MM / 2.0,
                    -CUTTER_OVERSHOOT_MM,
                ),
                DVec3::new(DECK_BOLT_COLUMN_PITCH_MM, 0.0, 0.0),
                3,
            )
        })
        .chain([left_cutter, right_cutter])
        .collect();
    let body = (flange + &left_tube + &right_tube).build()?;
    let mount = subtract_cutters(&body, &cutters)?;

    let step_path = robot_root()
        .join("assets")
        .join("meshes")
        .join("headrest_mount.step");
    Solid::write_step([&mount], &mut File::create(&step_path)?)?;
    println!("wrote {}", step_path.display());
    let viewer_mount = mount.align_z(-DVec3::Y, DVec3::X);
    write_solids_glb(&[viewer_mount], &step_path.with_extension("glb"))?;
    println!(
        "one piece; footprint {FLANGE_WIDTH_MM:.0}mm x {FLANGE_LENGTH_MM}mm, \
         sockets at {POLE_CENTER_SPACING_MM}mm centers"
    );
    println!(
        "six bolt holes {BOLT_HOLE_DIAMETER_MM}mm: columns at 0 and \
         +/-{DECK_BOLT_COLUMN_PITCH_MM}mm, rows at +/-{:.1}mm",
        DECK_BOLT_ROW_PITCH_MM / 2.0
    );
    println!(
        "bore {POLE_BORE_MM:.2}mm ({BORE_CLEARANCE_MM}mm clearance, coupon-calibrated)"
    );
    Ok(())
}
