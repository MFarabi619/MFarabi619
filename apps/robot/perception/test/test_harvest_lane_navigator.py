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


import re

from cv_bridge import CvBridge
from foxglove_msgs.msg import PointsAnnotation
import numpy as np
import pytest
from sensor_msgs.msg import CameraInfo

MASK_WIDTH = 640
MASK_HEIGHT = 480
FOCAL_LENGTH = 456.0
CENTER_COLUMN = 320.0
CENTER_ROW = 240.0
CAMERA_LATERAL_OFFSET_M = 0.5
CAMERA_HEIGHT_M = 0.31
ROW_WIDTH_M = 0.14
BRIDGE = CvBridge()


def camera_info():
    message = CameraInfo()
    message.width = MASK_WIDTH
    message.height = MASK_HEIGHT
    message.k = [FOCAL_LENGTH, 0.0, CENTER_COLUMN,
                 0.0, FOCAL_LENGTH, CENTER_ROW,
                 0.0, 0.0, 1.0]
    return message


def draw_row(mask, row_lateral_m, row_slope):
    for pixel_row in range(int(CENTER_ROW) + 8, MASK_HEIGHT):
        distance = FOCAL_LENGTH * CAMERA_HEIGHT_M / (pixel_row - CENTER_ROW)
        row_lateral = row_lateral_m + row_slope * distance
        center = CENTER_COLUMN + FOCAL_LENGTH * (
            CAMERA_LATERAL_OFFSET_M - row_lateral) / distance
        half_width = FOCAL_LENGTH * ROW_WIDTH_M / 2.0 / distance
        start = int(np.clip(center - half_width, 0, MASK_WIDTH))
        end = int(np.clip(center + half_width, 0, MASK_WIDTH))
        mask[pixel_row, start:end] = 255


def projected_mask(rows):
    mask = np.zeros((MASK_HEIGHT, MASK_WIDTH), np.uint8)
    for row_lateral_m, row_slope in rows:
        draw_row(mask, row_lateral_m, row_slope)
    return BRIDGE.cv2_to_compressed_imgmsg(mask, dst_format='png')


def capture(node):
    commands = []
    overlays = []
    node.cmd_vel_publisher.publish = commands.append
    node.overlay_publisher.publish = overlays.append
    node.on_camera_info(camera_info())
    return commands, overlays


def reported_lateral_error(overlay):
    label = overlay.texts[0].text
    return float(re.search(r'([+-]\d+\.\d+)', label).group(1))


def test_centered_row_drives_straight(harvest_lane_navigator_node):
    commands, overlays = capture(harvest_lane_navigator_node)
    harvest_lane_navigator_node.on_mask(projected_mask([(0.0, 0.0)]))
    assert len(commands) == 1
    assert commands[0].twist.linear.x == pytest.approx(0.4)
    assert commands[0].twist.angular.z == pytest.approx(0.0, abs=0.06)


def test_row_left_of_robot_steers_left(harvest_lane_navigator_node):
    commands, overlays = capture(harvest_lane_navigator_node)
    harvest_lane_navigator_node.on_mask(projected_mask([(0.15, 0.0)]))
    assert commands[0].twist.angular.z > 0.1


def test_row_right_of_robot_steers_right(harvest_lane_navigator_node):
    commands, overlays = capture(harvest_lane_navigator_node)
    harvest_lane_navigator_node.on_mask(projected_mask([(-0.15, 0.0)]))
    assert commands[0].twist.angular.z < -0.1


def test_heading_error_steers_to_realign(harvest_lane_navigator_node):
    commands, overlays = capture(harvest_lane_navigator_node)
    harvest_lane_navigator_node.on_mask(projected_mask([(0.0, 0.08)]))
    assert commands[0].twist.angular.z > 0.02


def test_offset_label_reports_meters(harvest_lane_navigator_node):
    commands, overlays = capture(harvest_lane_navigator_node)
    harvest_lane_navigator_node.on_mask(projected_mask([(0.15, 0.0)]))
    assert reported_lateral_error(overlays[0]) == pytest.approx(-0.15, abs=0.05)


def test_full_lattice_of_rows_agrees_on_center(harvest_lane_navigator_node):
    commands, overlays = capture(harvest_lane_navigator_node)
    harvest_lane_navigator_node.on_mask(
        projected_mask([(-1.2, 0.0), (0.0, 0.0), (1.2, 0.0)]))
    assert commands[0].twist.angular.z == pytest.approx(0.0, abs=0.06)


def test_offset_lattice_steers_back(harvest_lane_navigator_node):
    commands, overlays = capture(harvest_lane_navigator_node)
    harvest_lane_navigator_node.on_mask(
        projected_mask([(-1.05, 0.0), (0.15, 0.0), (1.35, 0.0)]))
    assert commands[0].twist.angular.z > 0.1


def test_overlay_draws_corridor_grid(harvest_lane_navigator_node):
    commands, overlays = capture(harvest_lane_navigator_node)
    harvest_lane_navigator_node.on_mask(projected_mask([(0.0, 0.0)]))
    center, left_track, right_track, rungs = overlays[0].points[:4]
    assert rungs.type == PointsAnnotation.LINE_LIST
    assert len(rungs.points) == 2 * len(center.points)
    for left, mid, right in zip(
            left_track.points, center.points, right_track.points):
        assert left.x < mid.x < right.x
    assert center.points[0].y > center.points[-1].y


def interpolated_column(points, image_row):
    for near, far in zip(points, points[1:]):
        if far.y <= image_row <= near.y:
            fraction = (image_row - near.y) / (far.y - near.y)
            return near.x + fraction * (far.x - near.x)
    return None


def test_corridor_center_overlays_the_lock_line(harvest_lane_navigator_node):
    commands, overlays = capture(harvest_lane_navigator_node)
    harvest_lane_navigator_node.on_mask(projected_mask([(0.15, 0.0)]))
    center = overlays[0].points[0]
    lock_line = overlays[0].points[4]
    overlapping = 0
    for lock_point in lock_line.points:
        column = interpolated_column(center.points, lock_point.y)
        if column is None:
            continue
        assert column == pytest.approx(lock_point.x, abs=12.0)
        overlapping += 1
    assert overlapping >= 3


def test_bare_mask_holds_position(harvest_lane_navigator_node):
    commands, overlays = capture(harvest_lane_navigator_node)
    harvest_lane_navigator_node.on_mask(projected_mask([]))
    assert commands == []
    assert overlays[0].points == []


def elevated_canopy(rows, foliage_height_m):
    mask = np.zeros((MASK_HEIGHT, MASK_WIDTH), np.uint8)
    depth = np.full((MASK_HEIGHT, MASK_WIDTH), np.inf, np.float32)
    camera_above_foliage = CAMERA_HEIGHT_M - foliage_height_m
    for pixel_row in range(int(CENTER_ROW) + 8, MASK_HEIGHT):
        distance = FOCAL_LENGTH * camera_above_foliage / (pixel_row - CENTER_ROW)
        for row_lateral_m, row_slope in rows:
            row_lateral = row_lateral_m + row_slope * distance
            center = CENTER_COLUMN + FOCAL_LENGTH * (
                CAMERA_LATERAL_OFFSET_M - row_lateral) / distance
            half_width = FOCAL_LENGTH * ROW_WIDTH_M / 2.0 / distance
            start = int(np.clip(center - half_width, 0, MASK_WIDTH))
            end = int(np.clip(center + half_width, 0, MASK_WIDTH))
            mask[pixel_row, start:end] = 255
            depth[pixel_row, start:end] = distance
    return (BRIDGE.cv2_to_compressed_imgmsg(mask, dst_format='png'),
            BRIDGE.cv2_to_imgmsg(depth))


def test_elevated_canopy_fools_flat_ground_fallback(harvest_lane_navigator_node):
    commands, overlays = capture(harvest_lane_navigator_node)
    mask, depth = elevated_canopy([(0.0, 0.0)], 0.15)
    harvest_lane_navigator_node.on_mask(mask)
    assert abs(commands[0].twist.angular.z) > 0.1


def test_depth_makes_elevated_canopy_exact(harvest_lane_navigator_node):
    commands, overlays = capture(harvest_lane_navigator_node)
    mask, depth = elevated_canopy([(0.0, 0.0)], 0.15)
    harvest_lane_navigator_node.on_depth(depth)
    harvest_lane_navigator_node.on_mask(mask)
    assert commands[0].twist.angular.z == pytest.approx(0.0, abs=0.06)


def test_depth_recovers_offset_of_elevated_canopy(harvest_lane_navigator_node):
    commands, overlays = capture(harvest_lane_navigator_node)
    mask, depth = elevated_canopy([(0.15, 0.0)], 0.15)
    harvest_lane_navigator_node.on_depth(depth)
    harvest_lane_navigator_node.on_mask(mask)
    assert reported_lateral_error(overlays[0]) == pytest.approx(-0.15, abs=0.05)


class FakeGoalHandle:
    def __init__(self, distance_m=0.0, forward_speed_mps=0.0):
        self.request = type('Request', (), {
            'travel_distance_m': distance_m, 'forward_speed_mps': forward_speed_mps})()
        self.is_cancel_requested = False
        self.feedbacks = []
        self.status = None

    def publish_feedback(self, feedback):
        self.feedbacks.append(feedback)

    def succeed(self):
        self.status = 'succeeded'

    def abort(self):
        self.status = 'aborted'

    def canceled(self):
        self.status = 'canceled'


def begin_goal(node, distance_m=0.0, forward_speed_mps=0.0):
    handle = FakeGoalHandle(distance_m, forward_speed_mps)
    node.goal_handle = handle
    node.goal_distance_m = distance_m
    node.goal_forward_speed_mps = forward_speed_mps
    node.distance_traveled_m = 0.0
    node.previous_odom_position = None
    node.row_miss_count = 0
    node.goal_outcome = None
    return handle


def odometry(x, y):
    from nav_msgs.msg import Odometry
    message = Odometry()
    message.pose.pose.position.x = float(x)
    message.pose.pose.position.y = float(y)
    return message


def test_goal_drives_and_streams_feedback(harvest_lane_navigator_node):
    harvest_lane_navigator_node.drive_enabled = False
    commands, overlays = capture(harvest_lane_navigator_node)
    handle = begin_goal(harvest_lane_navigator_node)
    harvest_lane_navigator_node.on_mask(projected_mask([(0.0, 0.0)]))
    assert len(commands) == 1
    assert len(handle.feedbacks) == 1
    assert handle.feedbacks[0].lateral_error_m == pytest.approx(0.0, abs=0.05)


def test_goal_speed_overrides_parameter(harvest_lane_navigator_node):
    harvest_lane_navigator_node.drive_enabled = False
    commands, overlays = capture(harvest_lane_navigator_node)
    begin_goal(harvest_lane_navigator_node, forward_speed_mps=0.8)
    harvest_lane_navigator_node.on_mask(projected_mask([(0.0, 0.0)]))
    assert commands[0].twist.linear.x == pytest.approx(0.8)


def test_odometry_reaches_goal_distance(harvest_lane_navigator_node):
    begin_goal(harvest_lane_navigator_node, distance_m=2.0)
    harvest_lane_navigator_node.on_odom(odometry(0.0, 0.0))
    harvest_lane_navigator_node.on_odom(odometry(1.2, 0.0))
    assert harvest_lane_navigator_node.goal_outcome is None
    harvest_lane_navigator_node.on_odom(odometry(2.1, 0.0))
    assert harvest_lane_navigator_node.goal_outcome == 'distance_reached'
    assert harvest_lane_navigator_node.distance_traveled_m == pytest.approx(2.1)


def test_losing_the_row_aborts_the_goal(harvest_lane_navigator_node):
    commands, overlays = capture(harvest_lane_navigator_node)
    begin_goal(harvest_lane_navigator_node, distance_m=10.0)
    for _ in range(12):
        harvest_lane_navigator_node.on_mask(projected_mask([]))
    assert harvest_lane_navigator_node.goal_outcome == 'row_lost'


def test_end_of_row_completes_untargeted_goal(harvest_lane_navigator_node):
    handle = begin_goal(harvest_lane_navigator_node)
    harvest_lane_navigator_node.distance_traveled_m = 5.0
    harvest_lane_navigator_node.conclude(handle, 'row_lost')
    assert handle.status == 'succeeded'


def test_row_lost_fails_distance_goal(harvest_lane_navigator_node):
    handle = begin_goal(harvest_lane_navigator_node, distance_m=10.0)
    harvest_lane_navigator_node.conclude(handle, 'row_lost')
    assert handle.status == 'aborted'


def test_phantom_row_lost_before_minimum_travel_fails(harvest_lane_navigator_node):
    handle = begin_goal(harvest_lane_navigator_node)
    harvest_lane_navigator_node.distance_traveled_m = 1.0
    harvest_lane_navigator_node.conclude(handle, 'row_lost')
    assert handle.status == 'aborted'


BED_LEAF_SPREAD_M = {-2.4: 0.4, -1.2: 0.12, 0.0: 0.12, 1.2: 0.12, 2.4: 0.4}
BED_PLANT_DRAWS = {-2.4: 20, -1.2: 6, 0.0: 6, 1.2: 6, 2.4: 20}


def scattered_canopy_mask(row_lateral_m, row_start_distance_m=0.8,
                          weed_fraction=0.02):
    generator = np.random.default_rng(3)
    mask = np.zeros((MASK_HEIGHT, MASK_WIDTH), np.uint8)
    for pixel_row in range(int(CENTER_ROW) + 4, MASK_HEIGHT):
        distance = FOCAL_LENGTH * CAMERA_HEIGHT_M / (pixel_row - CENTER_ROW)
        if distance < row_start_distance_m:
            continue
        for bed_offset, leaf_spread_m in BED_LEAF_SPREAD_M.items():
            for _ in range(BED_PLANT_DRAWS[bed_offset]):
                lateral = (row_lateral_m + bed_offset
                           + generator.normal(0.0, leaf_spread_m))
                column = CENTER_COLUMN + FOCAL_LENGTH * (
                    CAMERA_LATERAL_OFFSET_M - lateral) / distance
                blob_width = max(2, int(8.0 / distance))
                if 0 <= column < MASK_WIDTH and generator.random() < 0.7:
                    mask[pixel_row,
                         int(column):int(column) + blob_width] = 255
    weeds = generator.random((MASK_HEIGHT, MASK_WIDTH)) < weed_fraction
    weeds[:int(CENTER_ROW) + 4] = False
    mask[weeds] = 255
    return BRIDGE.cv2_to_compressed_imgmsg(mask, dst_format='png')


def test_scattered_real_canopy_still_locks(harvest_lane_navigator_node):
    commands, overlays = capture(harvest_lane_navigator_node)
    harvest_lane_navigator_node.on_mask(scattered_canopy_mask(0.15))
    assert len(commands) == 1
    assert reported_lateral_error(overlays[0]) == pytest.approx(-0.15, abs=0.07)


def test_row_starting_ahead_of_robot_still_locks(harvest_lane_navigator_node):
    commands, overlays = capture(harvest_lane_navigator_node)
    harvest_lane_navigator_node.on_mask(
        scattered_canopy_mask(0.0, row_start_distance_m=1.5))
    assert len(commands) == 1
    assert reported_lateral_error(overlays[0]) == pytest.approx(0.0, abs=0.07)


def speckle_mask(coverage_fraction):
    generator = np.random.default_rng(7)
    speckle = generator.random((MASK_HEIGHT, MASK_WIDTH)) < coverage_fraction
    return BRIDGE.cv2_to_compressed_imgmsg(
        speckle.astype(np.uint8) * 255, dst_format='png')


def test_grass_speckle_is_not_a_row(harvest_lane_navigator_node):
    commands, overlays = capture(harvest_lane_navigator_node)
    harvest_lane_navigator_node.on_mask(speckle_mask(0.25))
    assert commands == []
    assert overlays[0].points == []


def test_without_camera_info_stays_silent(harvest_lane_navigator_node):
    commands = []
    overlays = []
    harvest_lane_navigator_node.cmd_vel_publisher.publish = commands.append
    harvest_lane_navigator_node.overlay_publisher.publish = overlays.append
    harvest_lane_navigator_node.on_mask(projected_mask([(0.0, 0.0)]))
    assert commands == []
    assert overlays == []
