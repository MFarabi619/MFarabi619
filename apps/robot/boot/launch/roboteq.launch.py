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
import yaml
from zenoh_router import ensure_router

RESPAWN = {'max_respawns': -1, 'respawn_delay': 2.0}


def flash_declarations(flash):
    declarations = []
    for code, setting in flash.items():
        if isinstance(setting, dict):
            declarations += [
                f'{code} {channel} {value}'
                for channel, value in setting.items()
            ]
        else:
            declarations.append(f'{code} {setting}')
    return declarations


@launch_this
def roboteq(
    port: str = '/dev/cu.usbmodem2072356748451',
    baud: int = 115200,
    counts_per_revolution: int = 90,
    robot: str = 'taro',
):
    with open(f'machines/{robot}/robot.yaml') as machine_file:
        drivetrain = yaml.safe_load(machine_file)['platform']['drivetrain']
    flash = drivetrain.get('roboteq', {}).get('flash', {})
    bl = BetterLaunch()
    ensure_router(bl, env={'ZENOH_CONFIG_OVERRIDE': 'mode="router"'})
    bl.node(
        package='robot_drivers',
        executable='roboteq_motor_driver',
        name='roboteq_motor_driver',
        params={
            'serial_port': port,
            'baud_rate': baud,
            'counts_per_revolution': counts_per_revolution,
            'flash': flash_declarations(flash),
        },
        **RESPAWN,
    )
