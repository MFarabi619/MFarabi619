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


from types import SimpleNamespace

import cv2
import numpy as np
import pytest
import rclpy
from sensor_msgs.msg import CompressedImage
from std_srvs.srv import SetBool

LEFT_ELBOW = 13
RIGHT_ELBOW = 14
POSE_LANDMARK_COUNT = 33


class SingleResultLandmarker:
    def __init__(self, result):
        self.result = result

    def detect_for_video(self, image, timestamp_ms):
        return self.result


def landmark(x=0.5, y=0.5, visibility=1.0):
    return SimpleNamespace(x=x, y=y, visibility=visibility)


def pose(left_elbow=None, right_elbow=None):
    landmarks = [landmark(visibility=0.0) for _ in range(POSE_LANDMARK_COUNT)]
    if left_elbow is not None:
        landmarks[LEFT_ELBOW] = left_elbow
    if right_elbow is not None:
        landmarks[RIGHT_ELBOW] = right_elbow
    return SimpleNamespace(pose_landmarks=[landmarks])


def empty_pose():
    return SimpleNamespace(pose_landmarks=[])


def camera_frame():
    pixels = np.full((16, 16, 3), 128, np.uint8)
    encoded, jpeg = cv2.imencode('.jpg', pixels)
    assert encoded
    message = CompressedImage()
    message.format = 'jpeg'
    message.data = jpeg.tobytes()
    return message


def corrupt_frame():
    message = CompressedImage()
    message.format = 'jpeg'
    message.data = bytes([0, 1, 2, 3])
    return message


def capture(node):
    twists = []
    node.cmd_vel_publisher.publish = twists.append
    return twists


def feed(node, result, frames):
    node.landmarker = SingleResultLandmarker(result)
    for _ in range(frames):
        node.on_image(camera_frame())


def calibrate(node, elbow_y=0.5):
    feed(node, pose(left_elbow=landmark(y=elbow_y)), node.neutral_sample_frames)


def test_calibration_frames_hold_still(lay_down_weeding_elbow_teleop_node):
    node = lay_down_weeding_elbow_teleop_node
    twists = capture(node)
    calibrate(node)
    assert twists
    assert all(twist.twist.linear.x == 0.0 for twist in twists)


def test_elbow_pushed_forward_creeps_forward(lay_down_weeding_elbow_teleop_node):
    node = lay_down_weeding_elbow_teleop_node
    twists = capture(node)
    calibrate(node)
    feed(node, pose(left_elbow=landmark(y=0.6)), node.commit_frames)
    assert twists[-1].twist.linear.x == pytest.approx(node.forward_speed_mps)


def test_elbow_pulled_back_creeps_in_reverse(lay_down_weeding_elbow_teleop_node):
    node = lay_down_weeding_elbow_teleop_node
    twists = capture(node)
    calibrate(node)
    feed(node, pose(left_elbow=landmark(y=0.4)), node.commit_frames)
    assert twists[-1].twist.linear.x == pytest.approx(-node.reverse_speed_mps)


def test_elbow_near_neutral_holds(lay_down_weeding_elbow_teleop_node):
    node = lay_down_weeding_elbow_teleop_node
    twists = capture(node)
    calibrate(node)
    feed(node, pose(left_elbow=landmark(y=0.53)), node.commit_frames)
    assert twists
    assert all(twist.twist.linear.x == 0.0 for twist in twists)


def test_a_single_displaced_frame_does_not_commit(
        lay_down_weeding_elbow_teleop_node):
    node = lay_down_weeding_elbow_teleop_node
    twists = capture(node)
    calibrate(node)
    feed(node, pose(left_elbow=landmark(y=0.6)), 1)
    assert twists
    assert all(twist.twist.linear.x == 0.0 for twist in twists)


def test_an_inverted_drive_axis_flips_direction(
        lay_down_weeding_elbow_teleop_node):
    node = lay_down_weeding_elbow_teleop_node
    node.invert_drive_axis = True
    twists = capture(node)
    calibrate(node)
    feed(node, pose(left_elbow=landmark(y=0.6)), node.commit_frames)
    assert twists[-1].twist.linear.x == pytest.approx(-node.reverse_speed_mps)


def test_a_horizontal_drive_axis_reads_elbow_x(lay_down_weeding_elbow_teleop_node):
    node = lay_down_weeding_elbow_teleop_node
    node.drive_axis = 'x'
    twists = capture(node)
    calibrate(node)
    feed(node, pose(left_elbow=landmark(x=0.6)), node.commit_frames)
    assert twists[-1].twist.linear.x == pytest.approx(node.forward_speed_mps)


def test_a_zone_flip_halts_before_the_new_commit(
        lay_down_weeding_elbow_teleop_node):
    node = lay_down_weeding_elbow_teleop_node
    twists = capture(node)
    calibrate(node)
    feed(node, pose(left_elbow=landmark(y=0.6)), node.commit_frames)
    feed(node, pose(left_elbow=landmark(y=0.4)), 1)
    assert twists[-1].twist.linear.x == 0.0


def test_a_lost_operator_halts_the_creep(lay_down_weeding_elbow_teleop_node):
    node = lay_down_weeding_elbow_teleop_node
    twists = capture(node)
    calibrate(node)
    feed(node, pose(left_elbow=landmark(y=0.6)), node.commit_frames)
    feed(node, empty_pose(), 1)
    assert twists[-1].twist.linear.x == 0.0


def test_a_barely_visible_elbow_counts_as_absent(
        lay_down_weeding_elbow_teleop_node):
    node = lay_down_weeding_elbow_teleop_node
    twists = capture(node)
    calibrate(node)
    feed(node, pose(left_elbow=landmark(y=0.6, visibility=0.2)),
         node.commit_frames)
    assert twists
    assert all(twist.twist.linear.x == 0.0 for twist in twists)


def test_either_arm_follows_the_more_visible_elbow(
        lay_down_weeding_elbow_teleop_node):
    node = lay_down_weeding_elbow_teleop_node
    twists = capture(node)
    calibrate(node)
    feed(node,
         pose(left_elbow=landmark(y=0.6, visibility=0.9),
              right_elbow=landmark(y=0.5, visibility=0.6)),
         node.commit_frames)
    assert twists[-1].twist.linear.x == pytest.approx(node.forward_speed_mps)


def test_a_disabled_node_publishes_nothing(lay_down_weeding_elbow_teleop_node):
    node = lay_down_weeding_elbow_teleop_node
    node.is_enabled = False
    twists = capture(node)
    feed(node, pose(left_elbow=landmark(y=0.6)), node.commit_frames)
    assert twists == []


def test_reenabling_recalibrates_the_neutral_position(
        lay_down_weeding_elbow_teleop_node):
    node = lay_down_weeding_elbow_teleop_node
    twists = capture(node)
    calibrate(node)
    node.on_enable(SetBool.Request(data=True), SetBool.Response())
    calibrate(node, elbow_y=0.6)
    feed(node, pose(left_elbow=landmark(y=0.6)), node.commit_frames)
    assert twists
    assert all(twist.twist.linear.x == 0.0 for twist in twists)


def test_a_corrupt_frame_halts_the_creep(lay_down_weeding_elbow_teleop_node):
    node = lay_down_weeding_elbow_teleop_node
    twists = capture(node)
    calibrate(node)
    feed(node, pose(left_elbow=landmark(y=0.6)), node.commit_frames)
    node.on_image(corrupt_frame())
    assert twists[-1].twist.linear.x == 0.0


def test_calibration_locks_onto_one_elbow(lay_down_weeding_elbow_teleop_node):
    node = lay_down_weeding_elbow_teleop_node
    twists = capture(node)
    calibrate(node)
    feed(node, pose(right_elbow=landmark(y=0.6)), node.commit_frames)
    assert twists
    assert all(twist.twist.linear.x == 0.0 for twist in twists)


def test_recalibration_can_follow_the_other_arm(
        lay_down_weeding_elbow_teleop_node):
    node = lay_down_weeding_elbow_teleop_node
    twists = capture(node)
    calibrate(node)
    node.on_enable(SetBool.Request(data=True), SetBool.Response())
    feed(node, pose(right_elbow=landmark(y=0.5)), node.neutral_sample_frames)
    feed(node, pose(right_elbow=landmark(y=0.6)), node.commit_frames)
    assert twists[-1].twist.linear.x == pytest.approx(node.forward_speed_mps)


def test_an_interrupted_calibration_starts_over(
        lay_down_weeding_elbow_teleop_node):
    node = lay_down_weeding_elbow_teleop_node
    twists = capture(node)
    feed(node, pose(left_elbow=landmark(y=0.4)), 2)
    feed(node, empty_pose(), 1)
    feed(node, pose(left_elbow=landmark(y=0.6)), node.neutral_sample_frames)
    feed(node, pose(left_elbow=landmark(y=0.6)), node.commit_frames)
    assert twists
    assert all(twist.twist.linear.x == 0.0 for twist in twists)


def test_changing_the_drive_axis_recalibrates(
        lay_down_weeding_elbow_teleop_node):
    node = lay_down_weeding_elbow_teleop_node
    capture(node)
    calibrate(node)
    node.on_parameters_set(
        [rclpy.parameter.Parameter('drive_axis', value='x')])
    assert node.drive_axis == 'x'
    assert node.neutral_position is None


def test_inverting_the_drive_axis_applies_live(
        lay_down_weeding_elbow_teleop_node):
    node = lay_down_weeding_elbow_teleop_node
    capture(node)
    node.on_parameters_set(
        [rclpy.parameter.Parameter('invert_drive_axis', value=True)])
    assert node.invert_drive_axis is True


def test_disabling_publishes_a_final_halt(lay_down_weeding_elbow_teleop_node):
    node = lay_down_weeding_elbow_teleop_node
    twists = capture(node)
    node.on_enable(SetBool.Request(data=False), SetBool.Response())
    assert twists[-1].twist.linear.x == 0.0
