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

IMU_TOPICS = (
    'data', 'mag', 'linear_acceleration', 'stability',
    'activity', 'steps', 'shake', 'calibration_status',
)


@launch_this
def imu(
    i2c_bus: int = 1,
    i2c_address: int = 74,
    frame_id: str = 'imu_0_link',
    rate_hz: float = 25.0,
    topic_prefix: str = 'sensors/imu_0',
):
    bl = BetterLaunch()
    ensure_router(bl)
    bl.node(
        package='robot_drivers',
        executable='imu',
        name='imu_0',
        remaps={topic: f'{topic_prefix}/{topic}' for topic in IMU_TOPICS},
        params={
            'i2c_bus': i2c_bus,
            'i2c_address': i2c_address,
            'frame_id': frame_id,
            'rate_hz': rate_hz,
        },
        **RESPAWN,
    )
