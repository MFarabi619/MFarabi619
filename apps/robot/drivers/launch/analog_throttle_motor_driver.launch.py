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
def analog_throttle_motor_driver(
    i2c_bus: int = 1,
    gpio_chip: int = 0,
    full_scale_wheel_speed: float = 1.0,
    min_throttle_volts: float = 0.0,
    max_throttle_volts: float = 5.0,
    dac_supply_volts: float = 5.0,
    reverse_dwell_seconds: float = 0.5,
    left_dac_i2c_address: int = 0x62,
    left_reverse_switch_line: int = 0,
    left_is_reversed: bool = False,
    right_dac_i2c_address: int = 0x63,
    right_reverse_switch_line: int = 1,
    right_is_reversed: bool = False,
):
    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    bl.node(
        package='robot_drivers',
        executable='analog_throttle_motor_driver',
        params={
            'i2c_bus': i2c_bus,
            'gpio_chip': gpio_chip,
            'full_scale_wheel_speed': full_scale_wheel_speed,
            'min_throttle_volts': min_throttle_volts,
            'max_throttle_volts': max_throttle_volts,
            'dac_supply_volts': dac_supply_volts,
            'reverse_dwell_seconds': reverse_dwell_seconds,
            'left_dac_i2c_address': left_dac_i2c_address,
            'left_reverse_switch_line': left_reverse_switch_line,
            'left_is_reversed': left_is_reversed,
            'right_dac_i2c_address': right_dac_i2c_address,
            'right_reverse_switch_line': right_reverse_switch_line,
            'right_is_reversed': right_is_reversed,
        },
        **RESPAWN,
    )
