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

import pytest
import rclpy

SRC_DIRECTORY = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'src'))


def load_module(module_name):
    path = os.path.join(SRC_DIRECTORY, f'{module_name}.py')
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_node_class(module_name, class_name):
    return getattr(load_module(module_name), class_name)


@pytest.fixture(scope='session', autouse=True)
def ros_context():
    rclpy.init()
    yield
    rclpy.shutdown()


@pytest.fixture
def tracked_approach_node():
    node = load_node_class('tracked_approach', 'Approach')()
    yield node
    node.destroy_node()


@pytest.fixture
def row_follow_node():
    node = load_node_class('row_follow', 'RowFollow')()
    yield node
    node.destroy_node()


@pytest.fixture
def green_detector_node():
    node = load_node_class('green_detector', 'GreenDetector')()
    yield node
    node.destroy_node()


@pytest.fixture
def row_navigator_node():
    node = load_node_class('row_navigator', 'RowNavigator')()
    node.drive_enabled = True
    yield node
    node.destroy_node()


@pytest.fixture
def canopy_detector_node():
    node = load_node_class('canopy_detector', 'CanopyDetector')()
    yield node
    node.destroy_node()


@pytest.fixture
def cloud_optical_relay_node():
    node = load_node_class('cloud_optical_relay', 'CloudOpticalRelay')()
    yield node
    node.destroy_node()


@pytest.fixture
def harvest_lane_navigator_node():
    node = load_node_class('harvest_lane_navigator', 'HarvestLaneNavigator')()
    node.drive_enabled = True
    yield node
    node.destroy_node()
