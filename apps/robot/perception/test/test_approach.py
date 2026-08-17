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


def persons(*entries):
    message = Detection2DArray()
    for track_id, x, z in entries:
        detection = Detection2D()
        detection.id = str(track_id) if track_id is not None else ''
        hypothesis = ObjectHypothesisWithPose()
        hypothesis.hypothesis.class_id = 'person'
        hypothesis.hypothesis.score = 1.0
        hypothesis.pose.pose.position = Point(x=float(x), y=0.0, z=float(z))
        detection.results.append(hypothesis)
        message.detections.append(detection)
    return message


def capture(node):
    twists = []
    node.cmd_vel_publisher.publish = twists.append
    node.is_enabled = True
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


def test_keeps_tracked_id_over_slightly_nearer_stranger(approach_node):
    capture(approach_node)
    approach_node.on_detections(persons((7, 0.0, 2.0)))
    assert approach_node.tracked_id == 7
    approach_node.on_detections(persons((7, 1.0, 2.2), (9, 0.0, 2.0)))
    assert approach_node.tracked_id == 7
    assert approach_node.tracked_position.x == pytest.approx(1.0)


def test_switches_to_substantially_nearer_person(approach_node):
    capture(approach_node)
    approach_node.on_detections(persons((7, 0.0, 2.2)))
    approach_node.on_detections(persons((7, 0.0, 2.2), (9, 0.0, 1.5)))
    assert approach_node.tracked_id == 9


def test_position_fallback_bridges_lost_id(approach_node):
    capture(approach_node)
    approach_node.on_detections(persons((7, 0.5, 2.0)))
    approach_node.on_detections(persons((None, 0.55, 2.05)))
    assert approach_node.tracked_id is None
    assert approach_node.tracked_position.x == pytest.approx(0.55)


def test_crossing_people_do_not_swap_target(approach_node):
    capture(approach_node)
    approach_node.on_detections(persons((7, 0.5, 2.0)))
    approach_node.on_detections(persons((7, 0.6, 2.1), (9, 0.5, 2.0)))
    assert approach_node.tracked_id == 7
    assert approach_node.tracked_position.x == pytest.approx(0.6)


def test_reacquire_timeout_clears_id_and_position(approach_node):
    capture(approach_node)
    approach_node.max_missing_frames = 1
    approach_node.on_detections(persons((7, 0.0, 2.0)))
    approach_node.on_detections(Detection2DArray())
    approach_node.on_detections(Detection2DArray())
    assert approach_node.tracked_id is None
    assert approach_node.tracked_position is None


def test_holds_last_bearing_within_reacquire_window(approach_node):
    approach_node.max_missing_frames = 3
    twists = capture(approach_node)
    approach_node.on_detections(cones((1.0, 0.0, 2.0)))
    approach_node.on_detections(Detection2DArray())
    assert twists[-1].twist.linear.x == pytest.approx(0.0)
    assert twists[-1].twist.angular.z == pytest.approx(-0.6)


def test_halts_after_reacquire_window(approach_node):
    approach_node.max_missing_frames = 2
    twists = capture(approach_node)
    approach_node.on_detections(cones((1.0, 0.0, 2.0)))
    for _ in range(3):
        approach_node.on_detections(Detection2DArray())
    assert twists[-1].twist.linear.x == pytest.approx(0.0)
    assert twists[-1].twist.angular.z == pytest.approx(0.0)
