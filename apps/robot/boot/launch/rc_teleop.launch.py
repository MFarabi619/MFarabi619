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


from better_launch import BetterLaunch, launch_this
from robot_boot.launch_policy import RESPAWN
from robot_boot.zenoh_router import ensure_router


@launch_this
def rc_teleop(
    gpio_chip: str = 'gpiochip0',
    channel_1_line: int = 0,
    channel_2_line: int = 1,
    tank_mixed: bool = False,
    params_file: str = '',
):
    bl = BetterLaunch()
    ensure_router(bl)
    params_file = params_file or bl.find('robot_boot', 'rc_teleop.yaml')
    bl.node(
        package='robot_drivers',
        executable='rc_receiver_joy',
        name='rc_receiver_joy',
        params={
            'gpio_chip': gpio_chip,
            'channel_1_line': channel_1_line,
            'channel_2_line': channel_2_line,
            'tank_mixed': tank_mixed,
        },
        remaps={'joy': 'joy_teleop/joy'},
        **RESPAWN,
    )
    bl.node(
        package='teleop_twist_joy',
        executable='teleop_node',
        name='rc_teleop',
        param_files=[params_file],
        remaps={
            'joy': 'joy_teleop/joy',
            'cmd_vel': 'joy_teleop/cmd_vel',
        },
        **RESPAWN,
    )
