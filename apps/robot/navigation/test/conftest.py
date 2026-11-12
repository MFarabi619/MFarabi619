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


import importlib.util
import os
import sys

import pytest
import rclpy

SOURCE_DIRECTORY = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'src'))
PERCEPTION_SOURCE_DIRECTORY = os.path.abspath(
    os.path.join(os.path.dirname(__file__), '..', '..', 'perception', 'src'))
for directory in (PERCEPTION_SOURCE_DIRECTORY, SOURCE_DIRECTORY):
    if directory not in sys.path:
        sys.path.insert(0, directory)


def load_module(module_name):
    path = os.path.join(SOURCE_DIRECTORY, f'{module_name}.py')
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_node_class(module_name, class_name):
    return getattr(load_module(module_name), class_name)


@pytest.fixture(scope='session', autouse=True)
def ros_context():
    owns_context = not rclpy.ok()
    if owns_context:
        rclpy.init()
    yield
    if owns_context and rclpy.ok():
        rclpy.shutdown()


@pytest.fixture
def follow_node():
    node = load_node_class('follow', 'Follow')()
    node.is_enabled = True
    yield node
    node.destroy_node()


@pytest.fixture
def tracked_approach_node():
    node = load_node_class('tracked_approach', 'TrackedApproach')()
    yield node
    node.destroy_node()


@pytest.fixture
def line_follow_node():
    node = load_node_class('line_follow', 'LineFollow')()
    node.is_enabled = True
    yield node
    node.destroy_node()


@pytest.fixture
def surface_follow_node():
    node = load_node_class('surface_follow', 'SurfaceFollow')()
    node.is_enabled = True
    yield node
    node.destroy_node()


@pytest.fixture
def row_navigator_node():
    node = load_node_class('row_navigator', 'RowNavigator')()
    node.drive_enabled = True
    yield node
    node.destroy_node()


@pytest.fixture(scope='session')
def voice_teleop_module():
    return load_module('voice_teleop')


@pytest.fixture
def voice_teleop_node(voice_teleop_module):
    node = voice_teleop_module.VoiceTeleop()
    node.is_enabled = True
    yield node
    node.destroy_node()


@pytest.fixture(scope='module')
def row_shuttle():
    return load_module('row_shuttle')


@pytest.fixture
def lay_down_weeding_elbow_teleop_node():
    node = load_node_class(
        'lay_down_weeding_elbow_teleop', 'LayDownWeedingElbowTeleop')(
        parameter_overrides=[
            rclpy.parameter.Parameter('neutral_sample_frames', value=4),
            rclpy.parameter.Parameter('commit_frames', value=2),
            rclpy.parameter.Parameter('command_smoothing_seconds', value=0.0),
            rclpy.parameter.Parameter('max_detections_per_second', value=0.0),
        ])
    pose_landmarker = node.landmarker
    node.is_enabled = True
    yield node
    node.destroy_node()
    pose_landmarker.close()


@pytest.fixture
def harvest_lane_navigator_node():
    node = load_node_class('harvest_lane_navigator', 'HarvestLaneNavigator')()
    node.is_enabled = True
    yield node
    node.destroy_node()
