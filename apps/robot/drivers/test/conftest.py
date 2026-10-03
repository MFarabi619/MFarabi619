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


class ScriptedSerialPort:
    def __init__(self):
        self.written = []
        self.read_queue = []

    def write(self, data):
        self.written.append(bytes(data))

    def read_until(self, expected=b'\n'):
        return self.read_queue.pop(0) if self.read_queue else b''

    def reset_input_buffer(self):
        pass

    def close(self):
        pass


@pytest.fixture(scope='session')
def roboteq_motor_driver_module():
    return load_module('roboteq_motor_driver')


@pytest.fixture
def make_roboteq_driver(roboteq_motor_driver_module, monkeypatch):
    nodes = []

    def make(connect_replies=(), **parameters):
        parameters = {
            'counts_per_revolution': 90,
            'max_wheel_speed': 10.0,
            **parameters,
        }
        parameters = {
            name: value for name, value in parameters.items()
            if value is not None
        }
        scripted_port = ScriptedSerialPort()
        scripted_port.read_queue = list(connect_replies)
        monkeypatch.setattr(
            roboteq_motor_driver_module.serial, 'Serial',
            lambda *args, **kwargs: scripted_port)
        node = roboteq_motor_driver_module.RoboteqMotorDriver(
            parameter_overrides=[
                rclpy.parameter.Parameter(name, value=value)
                for name, value in parameters.items()
            ])
        nodes.append(node)
        return node, scripted_port

    yield make
    for node in nodes:
        node.destroy_node()
