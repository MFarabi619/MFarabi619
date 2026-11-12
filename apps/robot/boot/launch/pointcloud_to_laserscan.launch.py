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
from robot_boot.launch_policy import RESPAWN, TF_REMAPS
from robot_boot.zenoh_router import ensure_router


@launch_this
def pointcloud_to_laserscan(
    camera: str = 'camera_0',
    target_frame: str = 'base_link',
    min_height: float = 0.1,
    max_height: float = 0.5,
    range_min: float = 0.25,
    range_max: float = 8.0,
    scan_time: float = 1.0 / 15,
):
    bl = BetterLaunch()
    ensure_router(bl)
    bl.node(
        package='pointcloud_to_laserscan',
        executable='pointcloud_to_laserscan_node',
        name=f'{camera}_pointcloud_to_laserscan',
        remaps=TF_REMAPS | {
            'cloud_in': f'sensors/{camera}/depth/points',
            'scan': f'sensors/{camera}/scan',
        },
        params={
            'target_frame': target_frame,
            'min_height': min_height,
            'max_height': max_height,
            'range_min': range_min,
            'range_max': range_max,
            'scan_time': scan_time,
        },
        **RESPAWN,
    )
