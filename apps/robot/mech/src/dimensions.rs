#[derive(Copy, Clone, PartialEq, Debug)]
pub struct Dimensions {
    pub frame_length_millimeters: f64,
    pub frame_width_millimeters: f64,
    pub frame_top_z_millimeters: f64,
    pub rear_axle_inset_millimeters: f64,
    pub has_deck_equipment: bool,
    pub has_cross_rails: bool,
}

#[rustfmt::skip]
pub const ROBOT_DIMENSIONS: &[(&str, Dimensions)] = &[
    ("taro", Dimensions { frame_length_millimeters: 1219.2, frame_width_millimeters: 1000.0, frame_top_z_millimeters: 300.0, rear_axle_inset_millimeters: 85.0, has_deck_equipment: true, has_cross_rails: false }),
    ("jiro", Dimensions { frame_length_millimeters: 750.0, frame_width_millimeters: 400.0, frame_top_z_millimeters: 300.0, rear_axle_inset_millimeters: 135.0, has_deck_equipment: false, has_cross_rails: true }),
    ("beagleyai", Dimensions { frame_length_millimeters: 1219.2, frame_width_millimeters: 1000.0, frame_top_z_millimeters: 300.0, rear_axle_inset_millimeters: 85.0, has_deck_equipment: true, has_cross_rails: false }),
    ("pocketbeagle-2", Dimensions { frame_length_millimeters: 1219.2, frame_width_millimeters: 1000.0, frame_top_z_millimeters: 300.0, rear_axle_inset_millimeters: 85.0, has_deck_equipment: true, has_cross_rails: false }),
];

pub fn for_robot(robot_name: &str) -> Option<Dimensions> {
    ROBOT_DIMENSIONS
        .iter()
        .find(|(name, _)| *name == robot_name)
        .map(|(_, dimensions)| *dimensions)
}
