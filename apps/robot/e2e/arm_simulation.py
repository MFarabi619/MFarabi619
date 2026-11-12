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


import pathlib
import re
import signal
import subprocess
import sys
import time

import pytest
import yaml

ANSI_ESCAPES = re.compile(r'\x1b\[[0-9;]*m')

ROBOT_ROOT = pathlib.Path(__file__).resolve().parents[1]
APPLE_PLACEMENT_TOLERANCE_METERS = 0.03
apple_rest_position = {}
APPLE_LIFTED_MINIMUM_METERS = 0.12
ARM_JOINTS = ['joint_1', 'joint_2', 'joint_3', 'joint_4', 'joint_5', 'joint_6']
HOME_TOLERANCE_RADIANS = 0.05
KNUCKLE_JOINT = 'robotiq_85_left_knuckle_joint'
KNUCKLE_CLOSED_MINIMUM_RADIANS = 0.5
KNUCKLE_OPEN_MAXIMUM_RADIANS = 0.05
KNUCKLE_HOLDING_RANGE_RADIANS = (0.05, 0.75)
SIMULATION_STARTUP_TIMEOUT_SECONDS = 120.0
SIMULATION_SHUTDOWN_TIMEOUT_SECONDS = 30.0
CONTROLLER_POLL_SECONDS = 5.0
GRIPPER_TIMEOUT_SECONDS = 60.0
PICK_TIMEOUT_SECONDS = 120.0
PLACE_TIMEOUT_SECONDS = 120.0
SETTLE_SECONDS = 2.0


def echo_once(topic):
    output = ANSI_ESCAPES.sub('', subprocess.run(
        ['ros2', 'topic', 'echo', topic, '--once'],
        capture_output=True, text=True, timeout=30, cwd=ROBOT_ROOT).stdout)
    document = []
    for line in output.splitlines():
        if line.startswith('---'):
            break
        if document or re.match(r'^[a-z_]+:', line):
            document.append(line)
    return yaml.safe_load('\n'.join(document))


def joint_positions():
    message = echo_once('/joint_states')
    return dict(zip(message['name'], message['position']))


def apple_position():
    message = echo_once('/free_joint_state_publisher/free_joint_states')
    for state in message['free_joints']:
        if state['name'] == 'apple':
            position = state['pose']['pose']['position']
            return (position['x'], position['y'], position['z'])
    raise AssertionError('apple missing from free joint states')


def send_gripper_goal(position_radians):
    subprocess.run(
        ['ros2', 'action', 'send_goal',
         '/robotiq_gripper_controller/gripper_cmd',
         'control_msgs/action/GripperCommand',
         f'{{command: {{position: {position_radians}, max_effort: 60.0}}}}'],
        check=True, capture_output=True, timeout=GRIPPER_TIMEOUT_SECONDS,
        cwd=ROBOT_ROOT)
    time.sleep(SETTLE_SECONDS)


@pytest.fixture(scope='session', autouse=True)
def mujoco_simulation():
    launch = subprocess.Popen(
        [sys.executable, 'simulation/launch/arm_mujoco.launch.py',
         '--robot', 'kinova-link-6', '--mode', 'moveit',
         '--headless', 'true'],
        cwd=ROBOT_ROOT)
    deadline = time.monotonic() + SIMULATION_STARTUP_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        if launch.poll() is not None:
            raise RuntimeError('simulation exited during startup')
        controllers = subprocess.run(
            ['ros2', 'control', 'list_controllers'],
            capture_output=True, text=True, timeout=30,
            cwd=ROBOT_ROOT).stdout
        if controllers.count('active') >= 3:
            break
        time.sleep(CONTROLLER_POLL_SECONDS)
    else:
        launch.send_signal(signal.SIGINT)
        raise RuntimeError('controllers never became active')
    yield
    launch.send_signal(signal.SIGINT)
    try:
        launch.wait(SIMULATION_SHUTDOWN_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        launch.kill()
        launch.wait()


def test_gripper_round_trip():
    """The gripper action closes and reopens the fingers through
    position_controllers/GripperActionController."""
    send_gripper_goal(0.8)
    assert joint_positions()[KNUCKLE_JOINT] > KNUCKLE_CLOSED_MINIMUM_RADIANS
    send_gripper_goal(0.0)
    assert joint_positions()[KNUCKLE_JOINT] < KNUCKLE_OPEN_MAXIMUM_RADIANS


def test_picks_apple():
    """The MTC pick task lifts the apple off the ground; the fingers stall
    on the fruit rather than closing fully."""
    apple_rest_position['before_pick'] = apple_position()
    pick = subprocess.run(
        [sys.executable, 'manipulation/launch/kinova_link6_pick.launch.py',
         '--target_object', 'apple'],
        capture_output=True, text=True, timeout=PICK_TIMEOUT_SECONDS,
        cwd=ROBOT_ROOT)
    assert pick.returncode == 0, pick.stdout + pick.stderr
    assert "picked 'apple'" in pick.stdout, pick.stdout + pick.stderr
    time.sleep(SETTLE_SECONDS)
    assert apple_position()[2] > APPLE_LIFTED_MINIMUM_METERS
    low, high = KNUCKLE_HOLDING_RANGE_RADIANS
    assert low < joint_positions()[KNUCKLE_JOINT] < high


def test_places_apple_back():
    """The place task returns the apple to its pre-pick pose, recorded by
    mujoco_planning_scene at attach time, then parks the arm at home."""
    place = subprocess.run(
        [sys.executable, 'manipulation/src/kinova_link6_place.py',
         '--object', 'apple'],
        capture_output=True, text=True, timeout=PLACE_TIMEOUT_SECONDS,
        cwd=ROBOT_ROOT)
    assert place.returncode == 0, place.stdout + place.stderr
    assert "placed 'apple'" in place.stdout, place.stdout + place.stderr
    time.sleep(SETTLE_SECONDS)
    assert apple_position() == pytest.approx(
        apple_rest_position['before_pick'],
        abs=APPLE_PLACEMENT_TOLERANCE_METERS)
    positions = joint_positions()
    for joint_name in ARM_JOINTS:
        assert abs(positions[joint_name]) < HOME_TOLERANCE_RADIANS, joint_name
