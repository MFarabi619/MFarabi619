#!/usr/bin/env python3

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


import subprocess

from better_launch import BetterLaunch, launch_this

SMOOTHER_INPUT_TOPIC = 'key_vel'
TELEOP_OUTPUT_TOPIC = 'joy_teleop/cmd_vel'


@launch_this
def teleop_xiao(smoothing_enabled: bool = False):
    bl = BetterLaunch()
    if smoothing_enabled:
        bl.node(
            package='nav2_velocity_smoother',
            executable='velocity_smoother',
            name='velocity_smoother',
            param_files=bl.find('robot_boot', 'velocity_smoother.yaml'),
            remaps={'cmd_vel': SMOOTHER_INPUT_TOPIC, 'cmd_vel_smoothed': TELEOP_OUTPUT_TOPIC},
        )
    teleop_topic = SMOOTHER_INPUT_TOPIC if smoothing_enabled else TELEOP_OUTPUT_TOPIC
    subprocess.run([
        'ros2', 'run', 'teleop_twist_keyboard', 'teleop_twist_keyboard',
        '--ros-args',
        '--params-file', bl.find('robot_boot', 'keyboard_teleop.yaml'),
        '-r', f'cmd_vel:={teleop_topic}',
    ])
    bl.shutdown('teleop exited')
