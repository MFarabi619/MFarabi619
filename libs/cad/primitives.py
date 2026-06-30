from pathlib import Path

from build123d import Align, Box, Cylinder, Pos, Rot, import_step
from bd_warehouse.fastener import SocketHeadCapScrew
from bd_warehouse.open_builds import VSlotLinearRail

from parameters import (
    BATTERY_STRAP_OVERHANG,
    BATTERY_STRAP_THICKNESS,
    BATTERY_STRAP_WIDTH,
    BEAM_PROFILE,
    CROSS_BEAM_LENGTH,
    DECK_THICKNESS,
    HAT_STANDOFF_HEIGHT,
    HAT_STANDOFF_RADIUS,
    LONG_BEAM_LENGTH,
    VERTICAL_POST_HEIGHT,
)

ASSETS_DIR = Path(__file__).resolve().parent / "assets"


def _with_base_at_origin(shape):
    bbox = shape.bounding_box()
    return Pos(-bbox.center().X, -bbox.center().Y, -bbox.min.Z) * shape


long_beam     = Rot(Y=90) * VSlotLinearRail("40x40", LONG_BEAM_LENGTH,     align=Align.CENTER)
cross_beam    = Rot(X=90) * VSlotLinearRail("40x40", CROSS_BEAM_LENGTH,    align=Align.CENTER)
vertical_post =             VSlotLinearRail("40x40", VERTICAL_POST_HEIGHT, align=Align.CENTER)
_deck_bolt_length = DECK_THICKNESS + BEAM_PROFILE
deck_bolt = SocketHeadCapScrew("M6-1", _deck_bolt_length)

hat_standoff = Cylinder(
    HAT_STANDOFF_RADIUS, HAT_STANDOFF_HEIGHT,
    align=(Align.CENTER, Align.CENTER, Align.MIN),
)

_raw_drive_wheel       = import_step(str(ASSETS_DIR / "motor_with_bracket_and_wheel.step"))
_wheel_assembly        = next(child for child in _raw_drive_wheel.children if child.label.startswith("14IN_WHEEL"))
_wheel_assembly_center = _wheel_assembly.bounding_box().center()
drive_wheel            = Pos(-_wheel_assembly_center.X, -_wheel_assembly_center.Y, -_wheel_assembly_center.Z) * _raw_drive_wheel
flipped_drive_wheel    = Rot(Z=180) * drive_wheel

_raw_cytron_hat = import_step(str(ASSETS_DIR / "cytron-hat-mdd10.step"))
hat_bbox        = _raw_cytron_hat.bounding_box()
cytron_hat      = _with_base_at_origin(_raw_cytron_hat)

_raw_battery = import_step(str(ASSETS_DIR / "18ah-battery.step"))
battery_bbox = _raw_battery.bounding_box()
battery      = _with_base_at_origin(_raw_battery)

_battery_strap_length = battery_bbox.size.Y + 2 * BATTERY_STRAP_OVERHANG
battery_strap = Box(
    BATTERY_STRAP_WIDTH, _battery_strap_length, BATTERY_STRAP_THICKNESS,
    align=(Align.CENTER, Align.CENTER, Align.MIN),
)
battery_anchor_bolt = SocketHeadCapScrew(
    "M5-0.8", battery_bbox.size.Z + BATTERY_STRAP_THICKNESS + DECK_THICKNESS,
)
