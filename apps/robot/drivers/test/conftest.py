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
import rclpy.parameter

SRC_DIRECTORY = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'src'))


def load_module(module_name):
    path = os.path.join(SRC_DIRECTORY, f'{module_name}.py')
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope='session', autouse=True)
def ros_context():
    owns_context = not rclpy.ok()
    if owns_context:
        rclpy.init()
    yield
    if owns_context and rclpy.ok():
        rclpy.shutdown()


@pytest.fixture(scope='session')
def reverse_beeper_module():
    return load_module('reverse_beeper')


@pytest.fixture
def reverse_beeper_node(reverse_beeper_module):
    node = reverse_beeper_module.ReverseBeeper()
    yield node
    node.destroy_node()


@pytest.fixture
def usb_webcam_node():
    node = load_module('usb_webcam').UsbWebcam(
        parameter_overrides=[
            rclpy.parameter.Parameter('device_index', value=99)])
    yield node
    node.destroy_node()
