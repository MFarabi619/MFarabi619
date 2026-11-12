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
import subprocess

from better_launch import BetterLaunch, launch_this
from robot_boot.zenoh_router import zenoh_bridging_peer_config_override
from robot_machines.machine import load_machine

TELEOP_OUTPUT_TOPIC = 'joy_teleop/cmd_vel'


@launch_this
def teleop_twist_keyboard(robot: str = 'taro'):
    namespace = load_machine(robot).namespace
    os.environ['ZENOH_CONFIG_OVERRIDE'] = zenoh_bridging_peer_config_override(robot)
    bl = BetterLaunch()
    namespace_remap = ['-r', f'__ns:=/{namespace}'] if namespace else []
    subprocess.run([
        'ros2', 'run', 'teleop_twist_keyboard', 'teleop_twist_keyboard',
        '--ros-args',
        '--params-file', bl.find('robot_boot', 'teleop_twist_keyboard.yaml'),
        *namespace_remap,
        '-r', f'cmd_vel:={TELEOP_OUTPUT_TOPIC}',
    ])
    bl.shutdown('teleop exited')
