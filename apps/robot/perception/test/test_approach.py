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

from rclpy.duration import Duration
from std_srvs.srv import SetBool
from vision_msgs.msg import (
    Detection3D,
    Detection3DArray,
    ObjectHypothesisWithPose,
)


TWIST_MUX_EXTERNAL_TIMEOUT_S = 0.5


def capture(node):
    twists = []
    node.cmd_vel_publisher.publish = twists.append
    node.scene_publisher.publish = lambda message: None
    return twists


def person_at(forward_m, lateral_m=0.0):
    message = Detection3DArray()
    message.header.frame_id = 'camera_0_color_optical_frame'
    detection = Detection3D()
    hypothesis = ObjectHypothesisWithPose()
    hypothesis.hypothesis.class_id = 'person'
    hypothesis.hypothesis.score = 0.9
    hypothesis.pose.pose.position.x = lateral_m
    hypothesis.pose.pose.position.y = 0.0
    hypothesis.pose.pose.position.z = forward_m
    detection.results.append(hypothesis)
    message.detections.append(detection)
    return message


def age_detections(node, seconds):
    node.latest_detection_time = node.get_clock().now() - Duration(seconds=seconds)


def test_detections_do_not_publish_directly(approach_node):
    """The timer owns publishing, so a detection only updates the command."""
    twists = capture(approach_node)
    approach_node.on_detections(person_at(3.0))
    assert twists == []
    assert approach_node.latest_command is not None


def test_the_timer_republishes_between_detections(approach_node):
    twists = capture(approach_node)
    approach_node.on_detections(person_at(3.0))
    for _ in range(5):
        approach_node.on_control_period()
    assert len(twists) == 5, 'a slow detector must still get a steady command stream'
    assert all(twist.twist.linear.x > 0.0 for twist in twists)


def test_the_timer_is_silent_before_any_detection(approach_node):
    twists = capture(approach_node)
    approach_node.on_control_period()
    assert twists == []


def test_stale_detections_halt_rather_than_coast(approach_node):
    twists = capture(approach_node)
    approach_node.on_detections(person_at(3.0))
    age_detections(approach_node, approach_node.target_timeout_seconds + 0.5)
    approach_node.on_control_period()
    assert len(twists) == 1
    assert twists[0].twist.linear.x == 0.0
    assert twists[0].twist.angular.z == 0.0


def test_a_control_timer_ticks_faster_than_the_mux_times_out(approach_node):
    """twist_mux drops the external input after 0.5 s, which is what turned a
    slow detector into a stop-start robot."""
    periods_s = [timer.timer_period_ns * 1e-9 for timer in approach_node.timers]
    assert periods_s, 'no control timer: cmd_vel would only appear on detections'
    assert min(periods_s) < TWIST_MUX_EXTERNAL_TIMEOUT_S / 2.0


def test_a_disabled_follower_publishes_nothing_from_the_timer(approach_node):
    twists = capture(approach_node)
    approach_node.on_enable(SetBool.Request(data=False), SetBool.Response())
    # Set the command after disabling: on_enable clears it, so leaving it unset
    # would exercise the empty-command branch instead of the enable gate.
    approach_node.on_detections(person_at(3.0))
    approach_node.latest_detection_time = approach_node.get_clock().now()
    published = len(twists)
    approach_node.on_control_period()
    assert len(twists) == published


def test_disabling_commands_a_stop(approach_node):
    twists = capture(approach_node)
    approach_node.on_detections(person_at(3.0))
    approach_node.on_enable(SetBool.Request(data=False), SetBool.Response())
    assert twists[-1].twist.linear.x == 0.0
    assert twists[-1].twist.angular.z == 0.0


def test_non_finite_commands_never_reach_the_driver(approach_node):
    twists = capture(approach_node)
    approach_node.drive(math.nan, math.nan)
    assert math.isfinite(twists[-1].twist.linear.x)
    assert math.isfinite(twists[-1].twist.angular.z)


def test_forward_speed_is_clamped_to_the_configured_limit(approach_node):
    twists = capture(approach_node)
    approach_node.publish_twist(1000.0, 0.0)
    assert twists[-1].twist.linear.x == approach_node.max_forward_speed
