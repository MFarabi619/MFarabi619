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
def adafruit_bno085(
    imu: str = 'imu_0',
    i2c_bus: int = 1,
    i2c_address: int = 0x4A,
    frame_id: str = '',
    publish_rate_hz: float = 25.0,
):
    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    with bl.group(f'sensors/{imu}'):
        bl.node(
            package='robot_drivers',
            executable='adafruit_bno085',
            name='adafruit_bno085',
            params={
                'i2c_bus': i2c_bus,
                'i2c_address': i2c_address,
                'frame_id': frame_id or f'{imu}_link',
                'publish_rate_hz': publish_rate_hz,
            },
            **RESPAWN,
        )
