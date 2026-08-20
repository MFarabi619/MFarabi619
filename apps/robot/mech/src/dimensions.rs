#[derive(Copy, Clone, PartialEq, Debug)]
pub struct Dimensions {
    pub frame_length_mm: f64,
    pub frame_width_mm: f64,
    pub frame_top_z_mm: f64,
    pub rear_axle_inset_mm: f64,
    pub has_deck_equipment: bool,
}

#[rustfmt::skip]
pub const ROBOT_DIMENSIONS: &[(&str, Dimensions)] = &[
    ("taro", Dimensions { frame_length_mm: 1219.2, frame_width_mm: 1000.0, frame_top_z_mm: 300.0, rear_axle_inset_mm: 85.0, has_deck_equipment: true }),
    ("jiro", Dimensions { frame_length_mm: 750.0, frame_width_mm: 400.0, frame_top_z_mm: 300.0, rear_axle_inset_mm: 135.0, has_deck_equipment: false }),
    ("robot2", Dimensions { frame_length_mm: 1219.2, frame_width_mm: 1000.0, frame_top_z_mm: 300.0, rear_axle_inset_mm: 85.0, has_deck_equipment: true }),
    ("robot3", Dimensions { frame_length_mm: 1219.2, frame_width_mm: 1000.0, frame_top_z_mm: 300.0, rear_axle_inset_mm: 85.0, has_deck_equipment: true }),
    ("robot4", Dimensions { frame_length_mm: 1219.2, frame_width_mm: 1000.0, frame_top_z_mm: 300.0, rear_axle_inset_mm: 85.0, has_deck_equipment: true }),
    ("robot5", Dimensions { frame_length_mm: 1219.2, frame_width_mm: 1000.0, frame_top_z_mm: 300.0, rear_axle_inset_mm: 85.0, has_deck_equipment: true }),
    ("robot6", Dimensions { frame_length_mm: 1219.2, frame_width_mm: 1000.0, frame_top_z_mm: 300.0, rear_axle_inset_mm: 85.0, has_deck_equipment: true }),
];

pub fn for_robot(robot_name: &str) -> Option<Dimensions> {
    ROBOT_DIMENSIONS
        .iter()
        .find(|(name, _)| *name == robot_name)
        .map(|(_, dimensions)| *dimensions)
}
