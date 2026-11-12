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
from unittest import mock

import pytest

from launch_recording import (
    LaunchRecorder, isolate_launch_environment, launch_function, load_launch)
from launch_snapshot import assert_matches_snapshot, snapshot_payload, write_snapshot

ROBOT_LAUNCH_PATH = 'boot/launch/robot.launch.py'
STEREOLABS_ZED_LAUNCH_PATH = 'drivers/launch/stereolabs_zed.launch.py'
SIMULATION_LAUNCH_PATH = 'simulation/launch/simulation.launch.py'


class LaunchCase(NamedTuple):
    file: str
    function: str
    arguments: dict


CASES = {
    'robot/taro': LaunchCase(ROBOT_LAUNCH_PATH, 'robot', {'robot': 'taro'}),
    'robot/taro-rc-pulse': LaunchCase(
        ROBOT_LAUNCH_PATH, 'robot', {'robot': 'taro', 'drivetrain_model': 'rc_pulse'}),
    'robot/jiro': LaunchCase(ROBOT_LAUNCH_PATH, 'robot', {'robot': 'jiro'}),
    'robot/kinova-link-6': LaunchCase(ROBOT_LAUNCH_PATH, 'robot', {'robot': 'kinova-link-6'}),
    'robot/beagleyai': LaunchCase(ROBOT_LAUNCH_PATH, 'robot', {'robot': 'beagleyai'}),
    'robot/pocketbeagle-2': LaunchCase(ROBOT_LAUNCH_PATH, 'robot', {'robot': 'pocketbeagle-2'}),
    'robot/saburo': LaunchCase(ROBOT_LAUNCH_PATH, 'robot', {'robot': 'saburo'}),
    'stereolabs_zed/default': LaunchCase(STEREOLABS_ZED_LAUNCH_PATH, 'stereolabs_zed', {}),
    'simulation/taro-jiro': LaunchCase(
        SIMULATION_LAUNCH_PATH, 'simulation', {'headless': True}),
}


STARTED_KINDS = ('node', 'component', 'process')


def started_nodes(recorder):
    return sorted(
        (event['namespace'], str(event.get('name')), str(event.get('executable')))
        for event in recorder.events
        if event['kind'] in STARTED_KINDS
        and event.get('executable') != recorder.zenoh_router_executable)


@pytest.mark.parametrize('robot', ['taro', 'saburo', 'kinova-link-6'])
def test_domains_partition_the_full_launch(robot, monkeypatch, tmp_path):
    def record_launch(domain):
        directory = tmp_path / (domain or 'all')
        directory.mkdir()
        recorder = LaunchRecorder(str(directory))
        isolate_launch_environment(recorder, monkeypatch)
        module = load_launch(ROBOT_LAUNCH_PATH)
        launch_function(module)(robot=robot, domain=domain)
        return module, recorder

    with mock.patch.dict(os.environ):
        module, full_launch_recorder = record_launch('')
        started_by_domain = []
        for domain in module.DOMAINS:
            started_by_domain += started_nodes(record_launch(domain)[1])
    assert sorted(started_by_domain) == started_nodes(full_launch_recorder)


@pytest.mark.parametrize('case_id', CASES)
def test_launch_starts_the_same_nodes_as_the_snapshot(case_id, launch_recorder):
    case = CASES[case_id]
    module = load_launch(case.file)
    launch = launch_function(module)
    assert launch.__name__ == case.function
    launch(**case.arguments)
    payload = snapshot_payload(launch_recorder, {
        'file': case.file,
        'function': case.function,
        'arguments': case.arguments,
        'launch_this': launch.launch_this_settings,
    })
    if os.environ.get('SNAPSHOT_UPDATE'):
        write_snapshot(case_id, payload)
    else:
        assert_matches_snapshot(case_id, payload)
