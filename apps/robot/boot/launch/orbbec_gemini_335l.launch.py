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
def orbbec_gemini_335l(
    camera: str = 'camera_0',
    color_width: int = 640,
    color_height: int = 480,
    color_fps: int = 30,
    jpeg_quality: int = 80,
    enable_depth: bool = True,
    depth_width: int = 848,
    depth_height: int = 480,
    depth_fps: int = 15,
    depth_decimation: int = 2,
    point_cloud: bool = True,
):
    bl = BetterLaunch()
    ensure_router(bl)
    bl.node(
        package='robot_drivers',
        executable='orbbec_gemini_335l',
        name='orbbec_gemini_335l',
        params={
            'color_width': color_width,
            'color_height': color_height,
            'color_fps': color_fps,
            'jpeg_quality': jpeg_quality,
            'enable_depth': enable_depth,
            'depth_width': depth_width,
            'depth_height': depth_height,
            'depth_fps': depth_fps,
            'depth_decimation': depth_decimation,
        },
        remaps={
            'color/image_raw': f'sensors/{camera}/color/image_raw',
            'color/image_raw/compressed': f'sensors/{camera}/color/image_raw/compressed',
            'color/camera_info': f'sensors/{camera}/color/camera_info',
            'depth/image_raw': f'sensors/{camera}/depth/image_raw',
            'depth/image_raw/compressed': f'sensors/{camera}/depth/image_raw/compressed',
            'depth/camera_info': f'sensors/{camera}/depth/camera_info',
        },
        **RESPAWN,
    )
    if enable_depth and point_cloud:
        bl.node(
            package='depth_image_proc',
            executable='point_cloud_xyz_node',
            name='depth_to_pointcloud',
            remaps={
                'image_rect': f'sensors/{camera}/depth/image_raw',
                'camera_info': f'sensors/{camera}/depth/camera_info',
                'points': f'sensors/{camera}/depth/points',
            },
            **RESPAWN,
        )
