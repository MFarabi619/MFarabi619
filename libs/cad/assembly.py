from build123d import Box, GridLocations, Pos

from parameters import (
    ALUMINUM,
    BATTERY_STRAP_OVERHANG,
    BATTERY_STRAP_THICKNESS,
    BATTERY_STRAP_X_SPACING,
    BEAM_PROFILE,
    BRACKET_RAIL_GAP,
    BRASS,
    DECK_BOLT_INSET,
    DECK_EDGE_INSET,
    DECK_LENGTH,
    DECK_THICKNESS,
    DECK_WIDTH,
    HAT_STANDOFF_HEIGHT,
    INSIDE_GAP_BETWEEN_BEAMS,
    LONG_BEAM_LENGTH,
    LOWER_RAIL_ABOVE_HUB,
    PCB,
    PI_MOUNT_HOLE_X_SPACING,
    PI_MOUNT_HOLE_Y_SPACING,
    PLASTIC,
    PLYWOOD,
    RUBBER,
    STEEL,
    VERTICAL_POST_HEIGHT,
    WHEEL_BRACKET_REACH,
    WHEEL_RADIUS,
)
from primitives import (
    battery,
    battery_anchor_bolt,
    battery_bbox,
    battery_strap,
    cross_beam,
    cytron_hat,
    deck_bolt,
    drive_wheel,
    flipped_drive_wheel,
    hat_bbox,
    hat_standoff,
    long_beam,
    vertical_post,
)

long_beam_y_offset  = (INSIDE_GAP_BETWEEN_BEAMS + BEAM_PROFILE) / 2
cross_beam_x_offset = (LONG_BEAM_LENGTH - BEAM_PROFILE) / 2
lower_rail_z        = WHEEL_RADIUS + LOWER_RAIL_ABOVE_HUB
upper_rail_z        = lower_rail_z + VERTICAL_POST_HEIGHT
post_z_center       = (lower_rail_z + upper_rail_z) / 2
deck_z              = lower_rail_z + BEAM_PROFILE / 2 + DECK_THICKNESS / 2
deck_top_z          = deck_z + DECK_THICKNESS / 2
deck_bolt_x_offset  = DECK_LENGTH / 2 - DECK_BOLT_INSET
wheel_y_offset      = long_beam_y_offset - BEAM_PROFILE / 2 - BRACKET_RAIL_GAP + WHEEL_BRACKET_REACH

rail_z_levels   = [lower_rail_z, upper_rail_z]
long_beam_grid  = GridLocations(0, 2 * long_beam_y_offset, 1, 2)
cross_beam_grid = GridLocations(2 * cross_beam_x_offset, 0, 2, 1)
post_grid       = GridLocations(2 * cross_beam_x_offset, 2 * long_beam_y_offset, 2, 2)

vslot_frame_parts = (
    [Pos(0, 0, z) * loc * long_beam     for z in rail_z_levels for loc in long_beam_grid]  +
    [Pos(0, 0, z) * loc * cross_beam    for z in rail_z_levels for loc in cross_beam_grid] +
    [Pos(0, 0, post_z_center) * loc * vertical_post for loc in post_grid]
)

deck_parts = [
    Pos(0, 0, deck_z) * Box(DECK_LENGTH, DECK_WIDTH, DECK_THICKNESS)
]

bolt_parts = [
    Pos(0, 0, deck_top_z) * loc * deck_bolt
    for loc in GridLocations(2 * deck_bolt_x_offset, 2 * long_beam_y_offset, 2, 2)
]

wheel_parts = [
    Pos(0, 0, WHEEL_RADIUS) * loc * (flipped_drive_wheel if loc.position.Y > 0 else drive_wheel)
    for loc in GridLocations(2 * cross_beam_x_offset, 2 * wheel_y_offset, 2, 2)
]

hat_x        = DECK_LENGTH / 2 - hat_bbox.size.X / 2 - DECK_EDGE_INSET
hat_bottom_z = deck_top_z + HAT_STANDOFF_HEIGHT
hat_parts    = [Pos(hat_x, 0, hat_bottom_z) * cytron_hat]
standoff_parts = [
    Pos(hat_x, 0, deck_top_z) * loc * hat_standoff
    for loc in GridLocations(PI_MOUNT_HOLE_X_SPACING, PI_MOUNT_HOLE_Y_SPACING, 2, 2)
]

battery_x     = -DECK_LENGTH / 2 + battery_bbox.size.X / 2 + DECK_EDGE_INSET
battery_top_z = deck_top_z + battery_bbox.size.Z
battery_parts = [Pos(battery_x, 0, deck_top_z) * battery]

strap_parts = [
    Pos(battery_x, 0, battery_top_z) * loc * battery_strap
    for loc in GridLocations(BATTERY_STRAP_X_SPACING, 0, 2, 1)
]

strap_anchor_y = battery_bbox.size.Y / 2 + BATTERY_STRAP_OVERHANG
anchor_parts = [
    Pos(battery_x, 0, battery_top_z + BATTERY_STRAP_THICKNESS) * loc * battery_anchor_bolt
    for loc in GridLocations(BATTERY_STRAP_X_SPACING, 2 * strap_anchor_y, 2, 2)
]

material_groups = [
    ("aluminum", ALUMINUM, vslot_frame_parts + strap_parts),
    ("plywood",  PLYWOOD,  deck_parts),
    ("steel",    STEEL,    bolt_parts + anchor_parts),
    ("brass",    BRASS,    standoff_parts),
    ("rubber",   RUBBER,   wheel_parts),
    ("pcb",      PCB,      hat_parts),
    ("plastic",  PLASTIC,  battery_parts),
]
