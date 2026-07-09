pub const WHEEL_RADIUS: f64 = 178.0;
pub const DRIVE_WHEEL_TRACK: f64 = 1054.0;
pub const WHEELBASE: f64 = 1060.0;

pub const RAIL_CROSS_WIDTH: f64 = 50.8;
pub const RAIL_CROSS_HEIGHT: f64 = 25.4;
pub const RAIL_WALL_THICKNESS: f64 = 3.175;
pub const RAIL_HOLE_DIAMETER: f64 = 5.0;
pub const RAIL_HOLE_SPACING: f64 = 12.7;
pub const RAIL_FILLET_RADIUS: f64 = 0.5;

pub const GUSSET_ARM_LENGTH: f64 = 57.15;
pub const GUSSET_ARM_WIDTH: f64 = 25.4;
pub const GUSSET_THICKNESS: f64 = 3.175;
pub const GUSSET_HOLE_DIAMETER: f64 = 4.9784;
pub const GUSSET_HOLE_PITCH: f64 = 12.7;
pub const GUSSET_HOLES_PER_ARM: usize = 5;

pub const RAIL_END_CAP_FLANGE_THICKNESS: f64 = 4.0;
pub const RAIL_END_CAP_BOSS_DEPTH: f64 = 7.0;
pub const RAIL_END_CAP_BOSS_WALL: f64 = 3.0;

pub const FRAME_LENGTH: f64 = 1150.0;
pub const FRAME_WIDTH: f64 = 1000.0;
pub const FRAME_TOP_Z: f64 = 300.0;

pub const EDGE_COINCIDENCE_EPSILON_MM: f64 = 1e-6;
pub const END_FACE_NORMAL_X_THRESHOLD: f64 = 0.99;
pub const CUTTER_OVERSHOOT_MM: f64 = 1.0;
pub const CAVITY_OVERSHOOT_MM: f64 = 0.5;

pub const PLYWOOD_COLOR: [u8; 3] = [0xc8, 0xa0, 0x6e];
pub const ALUMINUM_COLOR: [u8; 3] = [0xb0, 0xb3, 0xb8];
pub const STEEL_COLOR: [u8; 3] = [0x5a, 0x5d, 0x63];
pub const END_CAP_COLOR: [u8; 3] = [0xe0, 0x7a, 0x1a];
pub const TIRE_COLOR: [u8; 3] = [0x0c, 0x0c, 0x0c];
#[allow(dead_code)]
pub const BATTERY_COLOR: [u8; 3] = [0x14, 0x14, 0x14];
