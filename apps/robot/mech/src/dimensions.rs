#[derive(Copy, Clone, PartialEq, Debug)]
pub struct Dimensions {
    pub frame_length_mm: f64,
    pub frame_width_mm: f64,
    pub frame_top_z_mm: f64,
    pub rear_axle_inset_mm: f64,
    pub has_deck_equipment: bool,
    pub has_cross_rails: bool,
}

#[rustfmt::skip]
pub const ROBOT_DIMENSIONS: &[(&str, Dimensions)] = &[
    ("taro", Dimensions { frame_length_mm: 1219.2, frame_width_mm: 1000.0, frame_top_z_mm: 300.0, rear_axle_inset_mm: 85.0, has_deck_equipment: true, has_cross_rails: false }),
    ("jiro", Dimensions { frame_length_mm: 750.0, frame_width_mm: 400.0, frame_top_z_mm: 300.0, rear_axle_inset_mm: 135.0, has_deck_equipment: false, has_cross_rails: true }),
    ("robot2", Dimensions { frame_length_mm: 1219.2, frame_width_mm: 1000.0, frame_top_z_mm: 300.0, rear_axle_inset_mm: 85.0, has_deck_equipment: true, has_cross_rails: false }),
    ("robot3", Dimensions { frame_length_mm: 1219.2, frame_width_mm: 1000.0, frame_top_z_mm: 300.0, rear_axle_inset_mm: 85.0, has_deck_equipment: true, has_cross_rails: false }),
    ("robot4", Dimensions { frame_length_mm: 1219.2, frame_width_mm: 1000.0, frame_top_z_mm: 300.0, rear_axle_inset_mm: 85.0, has_deck_equipment: true, has_cross_rails: false }),
    ("robot5", Dimensions { frame_length_mm: 1219.2, frame_width_mm: 1000.0, frame_top_z_mm: 300.0, rear_axle_inset_mm: 85.0, has_deck_equipment: true, has_cross_rails: false }),
    ("robot6", Dimensions { frame_length_mm: 1219.2, frame_width_mm: 1000.0, frame_top_z_mm: 300.0, rear_axle_inset_mm: 85.0, has_deck_equipment: true, has_cross_rails: false }),
];

pub fn for_robot(robot_name: &str) -> Option<Dimensions> {
    ROBOT_DIMENSIONS
        .iter()
        .find(|(name, _)| *name == robot_name)
        .map(|(_, dimensions)| *dimensions)
}
