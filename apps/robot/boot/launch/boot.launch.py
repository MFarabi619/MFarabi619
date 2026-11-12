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
import sys

from better_launch import BetterLaunch, launch_this
from robot_boot.launch_policy import RESPAWN, include
from robot_boot.zenoh_router import ROUTER_PORT, ensure_router, wait_for_router
from robot_machines.machine import load_machine, machine_names

CLIENT_CONFIG_OVERRIDE = f'mode="client";connect/endpoints=["tcp/localhost:{ROUTER_PORT}"]'
BENCH_FOXGLOVE_SEND_BUFFER_LIMIT_BYTES = 1000000


def fleet_router_config_override():
    endpoints = [
        f'"tcp/{host.hostname}.local:{ROUTER_PORT}"'
        for name in machine_names()
        for host in load_machine(name).system.hosts]
    return f'connect/endpoints=[{",".join(endpoints)}]'


def robot_runs_on_this_host(robot):
    return load_machine(robot).board == 'macos'


@launch_this
def boot(gesture_camera: str = 'webcam', robot: str = 'taro'):
    bl = BetterLaunch()
    gesture_camera_topics = {
        'webcam': '/image',
        'robot': f'/{robot}/sensors/camera_0/color/image_raw/compressed',
    }
    if robot_runs_on_this_host(robot):
        bl.process(
            [sys.executable, bl.find('robot_boot', 'robot.launch.py'), '--name', robot],
            name=f'{robot}_stack',
            **RESPAWN,
        )
        wait_for_router()
    ensure_router(bl, env={'ZENOH_CONFIG_OVERRIDE': fleet_router_config_override()})
    os.environ['ZENOH_CONFIG_OVERRIDE'] = CLIENT_CONFIG_OVERRIDE
    if gesture_camera == 'webcam':
        bl.node(
            package='robot_drivers',
            executable='usb_webcam',
            name='usb_webcam',
            **RESPAWN,
        )
    include(
        'robot_boot', 'foxglove_bridge.launch.py',
        send_buffer_limit_bytes=BENCH_FOXGLOVE_SEND_BUFFER_LIMIT_BYTES)
    with bl.group(robot):
        include(
            'robot_perception', 'hand_gesture_teleop.launch.py',
            image_topic=gesture_camera_topics[gesture_camera],
            start_enabled=True,
        )
    bl.node(
        package='robot_perception',
        executable='foxglove_panels',
        name='foxglove_panels',
    )
