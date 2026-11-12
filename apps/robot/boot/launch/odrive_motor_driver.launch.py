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
def odrive_motor_driver(
    gear_ratio: float = 1.0,
    max_wheel_speed: float = 0.0,
    left_serial: str = '',
    left_reversed: bool = False,
    right_serial: str = '',
    right_reversed: bool = False,
):
    bl = BetterLaunch()
    ensure_router(bl)
    bl.node(
        package='robot_drivers',
        executable='odrive_motor_driver',
        params={
            'gear_ratio': gear_ratio,
            'max_wheel_speed': max_wheel_speed,
            'left_serial': left_serial,
            'left_reversed': left_reversed,
            'right_serial': right_serial,
            'right_reversed': right_reversed,
        },
        **RESPAWN,
    )
