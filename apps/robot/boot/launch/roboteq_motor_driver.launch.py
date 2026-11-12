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
def roboteq_motor_driver(
    serial_port: str = '/dev/ttyACM0',
    baud_rate: int = 115200,
    counts_per_revolution: int = 90,
    control_mode: str = 'speed',
    left_reversed: bool = False,
    right_reversed: bool = False,
    max_wheel_speed: float = 0.0,
    full_scale_wheel_speed: float = 0.0,
    flash: str = '',
):
    bl = BetterLaunch()
    ensure_router(bl)
    parameters = {
        'serial_port': serial_port,
        'baud_rate': baud_rate,
        'counts_per_revolution': counts_per_revolution,
        'control_mode': control_mode,
        'left_reversed': left_reversed,
        'right_reversed': right_reversed,
    }
    if max_wheel_speed:
        parameters['max_wheel_speed'] = max_wheel_speed
    if flash:
        parameters['flash'] = flash.split(',')
    if full_scale_wheel_speed:
        parameters['full_scale_wheel_speed'] = full_scale_wheel_speed
    bl.node(
        package='robot_drivers',
        executable='roboteq_motor_driver',
        params=parameters,
        **RESPAWN,
    )
