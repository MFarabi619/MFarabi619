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
def pwm_dir_motor_driver(
    gpio_chip: str = 'gpiochip0',
    pwm_frequency_hz: float = 20000.0,
    max_wheel_speed: float = 0.0,
    min_duty_fraction: float = 0.0,
    left_pwm_chip: int = 0,
    left_pwm_channel: int = 0,
    left_dir_line: int = 0,
    left_forward_level: bool = True,
    right_pwm_chip: int = 0,
    right_pwm_channel: int = 1,
    right_dir_line: int = 1,
    right_forward_level: bool = False,
):
    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    bl.node(
        package='robot_drivers',
        executable='pwm_dir_motor_driver',
        params={
            'gpio_chip': gpio_chip,
            'pwm_frequency_hz': pwm_frequency_hz,
            'max_wheel_speed': max_wheel_speed,
            'min_duty_fraction': min_duty_fraction,
            'left_pwm_chip': left_pwm_chip,
            'left_pwm_channel': left_pwm_channel,
            'left_dir_line': left_dir_line,
            'left_forward_level': left_forward_level,
            'right_pwm_chip': right_pwm_chip,
            'right_pwm_channel': right_pwm_channel,
            'right_dir_line': right_dir_line,
            'right_forward_level': right_forward_level,
        },
        **RESPAWN,
    )
