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
from robot_boot.zenoh_router import ensure_zenoh_router


@launch_this
def svd48v_motor_driver(
    serial_port: str = '/dev/ttyUSB0',
    baud_rate: int = 115200,
    max_wheel_speed: float = 0.0,
    acceleration_rpm_per_second: float = 0.0,
    speed_smoothing_time: float = 0.0,
    left_reversed: bool = False,
    right_reversed: bool = False,
):
    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    bl.node(
        package='robot_drivers',
        executable='svd48v_motor_driver',
        params={
            'serial_port': serial_port,
            'baud_rate': baud_rate,
            'max_wheel_speed': max_wheel_speed,
            'acceleration_rpm_per_second': acceleration_rpm_per_second,
            'speed_smoothing_time': speed_smoothing_time,
            'left_reversed': left_reversed,
            'right_reversed': right_reversed,
        },
        **RESPAWN,
    )
