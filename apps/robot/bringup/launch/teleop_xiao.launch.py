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

RAW_TOPIC = 'key_vel'
SMOOTHED_TOPIC = 'joy_teleop/cmd_vel'


@launch_this
def teleop_xiao(smooth: bool = False):
    bl = BetterLaunch()
    if smooth:
        bl.node(
            package='nav2_velocity_smoother',
            executable='velocity_smoother',
            name='velocity_smoother',
            param_files='config/velocity_smoother.yaml',
            remaps={'cmd_vel': RAW_TOPIC, 'cmd_vel_smoothed': SMOOTHED_TOPIC},
        )
    teleop_topic = RAW_TOPIC if smooth else SMOOTHED_TOPIC
    subprocess.run([
        'ros2', 'run', 'teleop_twist_keyboard', 'teleop_twist_keyboard',
        '--ros-args',
        '--params-file', 'config/keyboard_teleop.yaml',
        '-r', f'cmd_vel:={teleop_topic}',
    ])
    bl.shutdown('teleop exited')
