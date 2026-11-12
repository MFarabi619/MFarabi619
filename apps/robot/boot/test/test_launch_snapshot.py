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


import os
from typing import NamedTuple

import pytest

from launch_recording import launch_function, load_launch
from launch_snapshot import assert_matches_snapshot, snapshot_payload, write_snapshot

ROBOT_LAUNCH_PATH = 'boot/launch/robot.launch.py'
ZED_CAMERA_LAUNCH_PATH = 'boot/launch/zed_camera.launch.py'
SIMULATION_LAUNCH_PATH = 'simulation/launch/simulation.launch.py'


class LaunchCase(NamedTuple):
    path: str
    function: str
    arguments: dict


CASES = {
    'robot/taro': LaunchCase(ROBOT_LAUNCH_PATH, 'robot', {'name': 'taro'}),
    'robot/taro-rc-pulse': LaunchCase(
        ROBOT_LAUNCH_PATH, 'robot', {'name': 'taro', 'drivetrain_model': 'rc_pulse'}),
    'robot/jiro': LaunchCase(ROBOT_LAUNCH_PATH, 'robot', {'name': 'jiro'}),
    'robot/kinova-link-6': LaunchCase(ROBOT_LAUNCH_PATH, 'robot', {'name': 'kinova-link-6'}),
    'robot/beagleyai': LaunchCase(ROBOT_LAUNCH_PATH, 'robot', {'name': 'beagleyai'}),
    'robot/pocketbeagle-2': LaunchCase(ROBOT_LAUNCH_PATH, 'robot', {'name': 'pocketbeagle-2'}),
    'zed_camera/default': LaunchCase(ZED_CAMERA_LAUNCH_PATH, 'zed_camera', {}),
    'simulation/taro-jiro': LaunchCase(
        SIMULATION_LAUNCH_PATH, 'simulation', {'headless': True}),
}


@pytest.mark.parametrize('case_id', CASES)
def test_launch_starts_the_same_nodes_as_the_snapshot(case_id, launch_recorder):
    case = CASES[case_id]
    module = load_launch(case.path)
    launch = launch_function(module)
    assert launch.__name__ == case.function
    launch(**case.arguments)
    payload = snapshot_payload(launch_recorder, {
        'file': case.path,
        'function': case.function,
        'arguments': case.arguments,
        'launch_this': launch.launch_this_settings,
    })
    if os.environ.get('SNAPSHOT_UPDATE'):
        write_snapshot(case_id, payload)
    else:
        assert_matches_snapshot(case_id, payload)
