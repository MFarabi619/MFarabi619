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
def luxonis_oak_d_sr(
    camera: str = 'camera_0',
    frames_per_second: float = 15.0,
    jpeg_quality: int = 60,
    point_cloud_enabled: bool = True,
):
    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    with bl.group(f'sensors/{camera}'):
        bl.node(
            package='robot_drivers',
            executable='luxonis_oak_d_sr',
            name='luxonis_oak_d_sr',
            params={
                'frame_id': f'{camera}_color_optical_frame',
                'frames_per_second': frames_per_second,
                'jpeg_quality': jpeg_quality,
            },
            **RESPAWN,
        )
        if point_cloud_enabled:
            bl.node(
                package='depth_image_proc',
                executable='point_cloud_xyz_node',
                name='depth_to_pointcloud',
                remaps={
                    'image_rect': 'depth/image_raw',
                    'camera_info': 'depth/camera_info',
                    'points': 'depth/points',
                },
                **RESPAWN,
            )
