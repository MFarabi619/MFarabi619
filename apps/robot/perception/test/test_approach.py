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


from geometry_msgs.msg import Point
import pytest
from vision_msgs.msg import Detection2D, Detection2DArray, ObjectHypothesisWithPose


def cones(*positions):
    message = Detection2DArray()
    for x, y, z in positions:
        detection = Detection2D()
        detection.id = 'cone'
        hypothesis = ObjectHypothesisWithPose()
        hypothesis.hypothesis.class_id = 'cone'
        hypothesis.hypothesis.score = 1.0
        hypothesis.pose.pose.position = Point(x=float(x), y=float(y), z=float(z))
        detection.results.append(hypothesis)
        message.detections.append(detection)
    return message


def capture(node):
    twists = []
    node.cmd_vel_publisher.publish = twists.append
    node.enabled = True
    return twists


def test_drives_forward_toward_centered_cone(approach_node):
    twists = capture(approach_node)
    approach_node.on_detections(cones((0.0, 0.0, 3.0)))
    assert len(twists) == 1
    assert twists[0].twist.linear.x == pytest.approx(0.6)
    assert twists[0].twist.angular.z == pytest.approx(0.0)


def test_steers_toward_offset_cone(approach_node):
    twists = capture(approach_node)
    approach_node.on_detections(cones((1.0, 0.0, 2.0)))
    assert twists[0].twist.angular.z == pytest.approx(-0.6)
    assert twists[0].twist.linear.x == pytest.approx(0.6)


def test_holds_position_inside_standoff(approach_node):
    twists = capture(approach_node)
    approach_node.on_detections(cones((0.0, 0.0, 0.5)))
    assert twists[0].twist.linear.x == pytest.approx(0.0)


def test_picks_nearest_cone(approach_node):
    twists = capture(approach_node)
    approach_node.on_detections(cones((2.0, 0.0, 5.0), (0.0, 0.0, 2.0)))
    assert twists[0].twist.linear.x == pytest.approx(0.6)
    assert twists[0].twist.angular.z == pytest.approx(0.0)


def test_halts_on_no_cone(approach_node):
    twists = capture(approach_node)
    approach_node.on_detections(Detection2DArray())
    assert twists[0].twist.linear.x == pytest.approx(0.0)
    assert twists[0].twist.angular.z == pytest.approx(0.0)


def test_ignores_cone_without_depth(approach_node):
    twists = capture(approach_node)
    approach_node.on_detections(cones((0.0, 0.0, 0.0)))
    assert twists[0].twist.linear.x == pytest.approx(0.0)
    assert twists[0].twist.angular.z == pytest.approx(0.0)


def test_stays_still_when_disabled(approach_node):
    twists = []
    approach_node.cmd_vel_publisher.publish = twists.append
    approach_node.on_detections(cones((0.0, 0.0, 3.0)))
    assert twists == []
