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


def load_node_class(module_name, class_name):
    path = os.path.join(SRC_DIRECTORY, f'{module_name}.py')
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return getattr(module, class_name)


@pytest.fixture(scope='session', autouse=True)
def ros_context():
    rclpy.init()
    yield
    rclpy.shutdown()


@pytest.fixture
def approach_node():
    node = load_node_class('approach', 'Approach')()
    yield node
    node.destroy_node()


@pytest.fixture
def row_follow_node():
    node = load_node_class('row_follow', 'RowFollow')()
    yield node
    node.destroy_node()
