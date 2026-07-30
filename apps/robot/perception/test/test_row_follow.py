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


import pytest
from vision_msgs.msg import BoundingBox2D, Detection2D, Detection2DArray, Point2D, Pose2D


def strips(width, *centers):
    message = Detection2DArray()
    for center_x in centers:
        detection = Detection2D()
        detection.id = 'cone_row'
        detection.bbox = BoundingBox2D(
            center=Pose2D(position=Point2D(x=float(center_x), y=0.0), theta=0.0),
            size_x=float(width),
            size_y=100.0,
        )
        message.detections.append(detection)
    return message


def capture(node):
    twists = []
    node.cmd_vel_publisher.publish = twists.append
    return twists


def test_follows_centered_row(row_follow_node):
    twists = capture(row_follow_node)
    row_follow_node.on_detections(strips(60.0, 640.0))
    assert twists[0].twist.linear.x == pytest.approx(0.4)
    assert twists[0].twist.angular.z == pytest.approx(0.0)


def test_steers_toward_offset_row(row_follow_node):
    twists = capture(row_follow_node)
    row_follow_node.on_detections(strips(60.0, 960.0))
    assert twists[0].twist.angular.z == pytest.approx(-0.6)
    assert twists[0].twist.linear.x == pytest.approx(0.3)


def test_tracks_centermost_strip(row_follow_node):
    twists = capture(row_follow_node)
    row_follow_node.on_detections(strips(60.0, 200.0, 640.0))
    assert twists[0].twist.angular.z == pytest.approx(0.0)


def test_turns_at_end_of_row(row_follow_node):
    twists = capture(row_follow_node)
    for _ in range(row_follow_node.end_of_row_frames):
        row_follow_node.on_detections(Detection2DArray())
    assert row_follow_node.state == 'turn'
    assert twists[-1].twist.linear.x == pytest.approx(0.0)
    assert twists[-1].twist.angular.z == pytest.approx(0.6)


def test_reacquires_row_after_turn(row_follow_node):
    capture(row_follow_node)
    for _ in range(row_follow_node.end_of_row_frames):
        row_follow_node.on_detections(Detection2DArray())
    assert row_follow_node.state == 'turn'
    row_follow_node.on_detections(strips(60.0, 640.0))
    assert row_follow_node.state == 'follow'
