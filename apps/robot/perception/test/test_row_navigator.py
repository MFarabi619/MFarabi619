# Copyright 2026 Mumtahin Farabi
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.


import math

import pytest
from sensor_msgs.msg import LaserScan

BEAM_COUNT = 241
FIELD_OF_VIEW = 1.2
BED_PITCH = 1.2
PLANT_LINE_OFFSET = 0.1


def scan_from_plants(plants):
    message = LaserScan()
    message.angle_min = -FIELD_OF_VIEW / 2.0
    message.angle_max = FIELD_OF_VIEW / 2.0
    message.angle_increment = FIELD_OF_VIEW / (BEAM_COUNT - 1)
    message.range_min = 0.1
    message.range_max = 10.0
    ranges = [float('inf')] * BEAM_COUNT
    for x, y in plants:
        angle = math.atan2(y, x)
        index = round((angle - message.angle_min) / message.angle_increment)
        if 0 <= index < BEAM_COUNT:
            ranges[index] = min(ranges[index], math.hypot(x, y))
    message.ranges = ranges
    return message


def plant_line(y, start=0.5, end=3.5, spacing=0.3):
    count = int((end - start) / spacing) + 1
    return [(start + index * spacing, y) for index in range(count)]


def capture(node):
    commands = []
    paths = []
    node.cmd_vel_publisher.publish = commands.append
    node.path_publisher.publish = paths.append
    return commands, paths


def test_straddled_plant_lines_hold_center(row_navigator_node):
    commands, paths = capture(row_navigator_node)
    scan = scan_from_plants(
        plant_line(PLANT_LINE_OFFSET) + plant_line(-PLANT_LINE_OFFSET))
    row_navigator_node.on_scan(scan)
    assert len(commands) == 1
    assert commands[0].twist.linear.x == pytest.approx(0.4)
    assert commands[0].twist.angular.z == pytest.approx(0.0, abs=0.05)
    assert len(paths[0].poses) > 0


def test_lateral_offset_steers_back_toward_row(row_navigator_node):
    commands, paths = capture(row_navigator_node)
    drift = 0.06
    scan = scan_from_plants(
        plant_line(PLANT_LINE_OFFSET - drift) + plant_line(-PLANT_LINE_OFFSET - drift))
    row_navigator_node.on_scan(scan)
    assert len(commands) == 1
    assert commands[0].twist.angular.z < -0.01


def test_furrow_between_beds_ignores_far_rows(row_navigator_node):
    commands, paths = capture(row_navigator_node)
    scan = scan_from_plants(
        plant_line(BED_PITCH / 2.0) + plant_line(-BED_PITCH / 2.0)
        + plant_line(1.5 * BED_PITCH) + plant_line(-1.5 * BED_PITCH))
    row_navigator_node.on_scan(scan)
    assert len(commands) == 1
    assert commands[0].twist.linear.x == pytest.approx(0.4)
    assert commands[0].twist.angular.z == pytest.approx(0.0, abs=0.05)


def test_sparse_returns_publish_no_command(row_navigator_node):
    commands, paths = capture(row_navigator_node)
    scan = scan_from_plants([(1.0, 0.5), (2.0, 0.5), (1.5, -0.5)])
    row_navigator_node.on_scan(scan)
    assert commands == []
    assert paths[0].poses == []


def test_single_wall_follows_at_default_half_width(row_navigator_node):
    commands, paths = capture(row_navigator_node)
    scan = scan_from_plants(plant_line(0.5))
    row_navigator_node.on_scan(scan)
    assert len(commands) == 1
    assert commands[0].twist.angular.z == pytest.approx(0.0, abs=0.05)
