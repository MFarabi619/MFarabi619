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
import rclpy
from rclpy.duration import Duration
from sensor_msgs.msg import CameraInfo
from std_srvs.srv import SetBool
from vision_msgs.msg import BoundingBox2D, Detection2D, Detection2DArray, Point2D, Pose2D

IMAGE_WIDTH = 640
IMAGE_CENTER_X = IMAGE_WIDTH / 2.0


def surface_detections(*centers):
    message = Detection2DArray()
    for center_x in centers:
        detection = Detection2D()
        detection.id = 'sidewalk'
        detection.bbox = BoundingBox2D(
            center=Pose2D(position=Point2D(x=float(center_x), y=240.0), theta=0.0),
            size_x=120.0,
            size_y=200.0,
        )
        message.detections.append(detection)
    return message


def capture(node):
    twists = []
    node.cmd_vel_publisher.publish = twists.append
    return twists


def report_camera_width(node, width=IMAGE_WIDTH):
    message = CameraInfo(width=width, height=400)
    message.k = [282.726, 0.0, width / 2.0,
                 0.0, 282.599, 202.800,
                 0.0, 0.0, 1.0]
    node.on_camera_info(message)


def send_detections(node, message):
    node.on_detections(message)
    node.on_control_period()


def age_latest_surface_time(node, seconds):
    node.latest_surface_time = node.get_clock().now() - Duration(seconds=seconds)


def test_follows_centered_surface(surface_follow_node):
    twists = capture(surface_follow_node)
    report_camera_width(surface_follow_node)
    send_detections(surface_follow_node, surface_detections(IMAGE_CENTER_X))
    assert twists[0].twist.linear.x == pytest.approx(0.4)
    assert twists[0].twist.angular.z == pytest.approx(0.0)


def test_steers_toward_surface_right_of_center(surface_follow_node):
    twists = capture(surface_follow_node)
    report_camera_width(surface_follow_node)
    send_detections(surface_follow_node, surface_detections(480.0))
    assert twists[0].twist.angular.z == pytest.approx(-0.6)
    assert twists[0].twist.linear.x == pytest.approx(0.3)


def test_steers_toward_surface_left_of_center(surface_follow_node):
    twists = capture(surface_follow_node)
    report_camera_width(surface_follow_node)
    send_detections(surface_follow_node, surface_detections(160.0))
    assert twists[0].twist.angular.z == pytest.approx(0.6)


def test_tracks_centermost_surface(surface_follow_node):
    twists = capture(surface_follow_node)
    report_camera_width(surface_follow_node)
    send_detections(surface_follow_node, surface_detections(80.0, IMAGE_CENTER_X))
    assert twists[0].twist.angular.z == pytest.approx(0.0)


def test_normalizes_offset_by_reported_camera_width(surface_follow_node):
    twists = capture(surface_follow_node)
    report_camera_width(surface_follow_node, width=1280)
    send_detections(surface_follow_node, surface_detections(960.0))
    assert twists[0].twist.angular.z == pytest.approx(-0.6)


def test_ignores_implausible_camera_width(surface_follow_node):
    twists = capture(surface_follow_node)
    report_camera_width(surface_follow_node)
    report_camera_width(surface_follow_node, width=0)
    send_detections(surface_follow_node, surface_detections(480.0))
    assert twists[0].twist.angular.z == pytest.approx(-0.6)


def test_waits_for_camera_info_before_steering(surface_follow_node):
    twists = capture(surface_follow_node)
    send_detections(surface_follow_node, surface_detections(480.0))
    assert twists == []


def test_ignores_detections_while_disabled(surface_follow_node):
    twists = capture(surface_follow_node)
    report_camera_width(surface_follow_node)
    surface_follow_node.is_enabled = False
    send_detections(surface_follow_node, surface_detections(480.0))
    assert twists == []


def test_stays_stopped_until_a_surface_is_seen(surface_follow_node):
    twists = capture(surface_follow_node)
    report_camera_width(surface_follow_node)
    send_detections(surface_follow_node, Detection2DArray())
    assert twists[-1].twist.linear.x == pytest.approx(0.0)
    assert twists[-1].twist.angular.z == pytest.approx(0.0)


def test_coasts_straight_through_brief_dropout(surface_follow_node):
    twists = capture(surface_follow_node)
    report_camera_width(surface_follow_node)
    send_detections(surface_follow_node, surface_detections(480.0))
    send_detections(surface_follow_node, Detection2DArray())
    assert twists[-1].twist.linear.x == pytest.approx(0.3)
    assert twists[-1].twist.angular.z == pytest.approx(0.0)


def test_stops_when_surface_stays_stale(surface_follow_node):
    twists = capture(surface_follow_node)
    report_camera_width(surface_follow_node)
    send_detections(surface_follow_node, surface_detections(480.0))
    age_latest_surface_time(surface_follow_node, 10.0)
    send_detections(surface_follow_node, Detection2DArray())
    assert twists[-1].twist.linear.x == pytest.approx(0.0)
    assert twists[-1].twist.angular.z == pytest.approx(0.0)


def test_floors_a_zero_timeout_instead_of_freezing(surface_follow_node):
    twists = capture(surface_follow_node)
    report_camera_width(surface_follow_node)
    surface_follow_node.surface_timeout_seconds = 0.0
    send_detections(surface_follow_node, surface_detections(480.0))
    assert twists[-1].twist.linear.x == pytest.approx(0.3)


def test_rejects_non_finite_parameters(surface_follow_node):
    for name in ('forward_speed', 'max_angular_speed', 'surface_timeout_seconds'):
        for value in (float('nan'), float('inf')):
            result = surface_follow_node.set_parameters(
                [rclpy.parameter.Parameter(name, value=value)])
            assert not result[0].successful


def test_publishes_zero_even_when_speeds_are_not_finite(surface_follow_node):
    twists = capture(surface_follow_node)
    surface_follow_node.forward_speed = float('nan')
    surface_follow_node.max_angular_speed = float('nan')
    surface_follow_node.halt()
    surface_follow_node.drive(1.0, 1.0)
    assert all(
        math.isfinite(twist.twist.linear.x) and math.isfinite(twist.twist.angular.z)
        for twist in twists)
    assert twists[0].twist.linear.x == pytest.approx(0.0)
    assert twists[0].twist.angular.z == pytest.approx(0.0)


def test_publishes_zero_when_asked_to_drive_a_non_finite_speed(surface_follow_node):
    twists = capture(surface_follow_node)
    surface_follow_node.drive(float('nan'), float('nan'))
    surface_follow_node.drive(float('inf'), float('-inf'))
    assert all(
        math.isfinite(twist.twist.linear.x) and math.isfinite(twist.twist.angular.z)
        for twist in twists)
    assert twists[0].twist.linear.x == pytest.approx(0.0)
    assert twists[0].twist.angular.z == pytest.approx(0.0)


def test_halts_while_no_surface_sighting_is_recorded(surface_follow_node):
    twists = capture(surface_follow_node)
    report_camera_width(surface_follow_node)
    send_detections(surface_follow_node, surface_detections(480.0))
    surface_follow_node.latest_surface_time = None
    surface_follow_node.on_control_period()
    assert twists[-1].twist.linear.x == pytest.approx(0.0)
    assert twists[-1].twist.angular.z == pytest.approx(0.0)


def test_does_not_speed_up_when_the_surface_is_lost(surface_follow_node):
    twists = capture(surface_follow_node)
    report_camera_width(surface_follow_node)
    send_detections(surface_follow_node, surface_detections(480.0))
    tracking_speed = twists[-1].twist.linear.x
    send_detections(surface_follow_node, Detection2DArray())
    assert twists[-1].twist.linear.x <= tracking_speed


def surface_run(center_x, width, center_y=380.0):
    detection = Detection2D()
    detection.id = 'sidewalk'
    detection.bbox = BoundingBox2D(
        center=Pose2D(position=Point2D(x=float(center_x), y=center_y), theta=0.0),
        size_x=float(width),
        size_y=200.0,
    )
    return detection


def test_follows_the_surface_underfoot_not_the_one_nearer_frame_centre(
        surface_follow_node):
    report_camera_width(surface_follow_node)
    surface_follow_node.lateral_offset_m = 0.35
    underfoot = surface_run(400.0, 400.0)
    neighbour = surface_run(250.0, 60.0)
    alone = surface_follow_node.center_error([underfoot])
    together = surface_follow_node.center_error([underfoot, neighbour])
    assert together == pytest.approx(alone)


def test_follows_the_surface_underfoot_not_the_one_sitting_on_the_target(
        surface_follow_node):
    report_camera_width(surface_follow_node)
    surface_follow_node.lateral_offset_m = 0.35
    underfoot = surface_run(IMAGE_CENTER_X, 120.0)
    on_target = surface_run(147.0, 60.0)
    alone = surface_follow_node.center_error([underfoot])
    together = surface_follow_node.center_error([underfoot, on_target])
    assert together == pytest.approx(alone)
    assert abs(together) > 0.3


def test_riding_right_of_centre_steers_right_of_a_centred_surface(surface_follow_node):
    twists = capture(surface_follow_node)
    report_camera_width(surface_follow_node)
    surface_follow_node.lateral_offset_m = 0.35
    send_detections(surface_follow_node, surface_detections(IMAGE_CENTER_X))
    assert twists[-1].twist.angular.z < 0.0


def test_uncalibrated_camera_applies_no_lateral_bias(surface_follow_node):
    surface_follow_node.lateral_offset_m = 0.35
    surface_follow_node.on_camera_info(CameraInfo(width=IMAGE_WIDTH, height=400))
    assert surface_follow_node.focal_length_x is None
    assert surface_follow_node.target_offset(390.0) == 0.0


def test_unusable_camera_height_applies_no_lateral_bias(surface_follow_node):
    report_camera_width(surface_follow_node)
    surface_follow_node.lateral_offset_m = 0.35
    for height in (0.0, -0.4):
        surface_follow_node.camera_height_m = height
        assert surface_follow_node.target_offset(390.0) == 0.0


def test_rows_above_the_horizon_apply_no_lateral_bias(surface_follow_node):
    report_camera_width(surface_follow_node)
    surface_follow_node.lateral_offset_m = 0.35
    above = surface_follow_node.principal_point_y - 1.0
    assert surface_follow_node.target_offset(above) == 0.0


def test_lateral_offset_shrinks_in_pixels_as_the_surface_gets_further_away(
        surface_follow_node):
    report_camera_width(surface_follow_node)
    surface_follow_node.lateral_offset_m = 0.35
    near = abs(surface_follow_node.target_offset(390.0))
    far = abs(surface_follow_node.target_offset(260.0))
    assert 0.0 < far < near


def test_control_timer_publishes_without_new_detections(surface_follow_node):
    twists = capture(surface_follow_node)
    report_camera_width(surface_follow_node)
    surface_follow_node.on_detections(surface_detections(480.0))
    rclpy.spin_once(surface_follow_node, timeout_sec=0.5)
    assert twists
    assert twists[-1].twist.angular.z == pytest.approx(-0.6)


def test_keeps_commanding_between_detections(surface_follow_node):
    twists = capture(surface_follow_node)
    report_camera_width(surface_follow_node)
    send_detections(surface_follow_node, surface_detections(480.0))
    surface_follow_node.on_control_period()
    surface_follow_node.on_control_period()
    assert len(twists) == 3
    assert twists[-1].twist.angular.z == pytest.approx(twists[0].twist.angular.z)


def test_disable_publishes_stop(surface_follow_node):
    twists = capture(surface_follow_node)
    report_camera_width(surface_follow_node)
    send_detections(surface_follow_node, surface_detections(480.0))
    surface_follow_node.on_enable(SetBool.Request(data=False), SetBool.Response())
    assert twists[-1].twist.linear.x == pytest.approx(0.0)
    published = len(twists)
    send_detections(surface_follow_node, surface_detections(480.0))
    assert len(twists) == published


def test_never_commands_reverse(surface_follow_node):
    twists = capture(surface_follow_node)
    report_camera_width(surface_follow_node)
    surface_follow_node.lateral_offset_m = 30.0
    send_detections(surface_follow_node, surface_detections(480.0))
    assert twists[-1].twist.linear.x == pytest.approx(0.0)


def test_negative_forward_speed_never_commands_reverse(surface_follow_node):
    twists = capture(surface_follow_node)
    report_camera_width(surface_follow_node)
    surface_follow_node.forward_speed = -0.5
    send_detections(surface_follow_node, surface_detections(480.0))
    surface_follow_node.halt()
    assert all(twist.twist.linear.x >= 0.0 for twist in twists)


def test_clamps_angular_speed(surface_follow_node):
    twists = capture(surface_follow_node)
    report_camera_width(surface_follow_node)
    surface_follow_node.steer_gain = 100.0
    send_detections(surface_follow_node, surface_detections(0.0))
    assert abs(twists[-1].twist.angular.z) <= surface_follow_node.max_angular_speed
