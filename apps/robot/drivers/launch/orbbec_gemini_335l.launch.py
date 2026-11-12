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
from robot_boot.launch_policy import DEFAULT_DEPTH_FRAMES_PER_SECOND, RESPAWN
from robot_boot.zenoh_router import ensure_zenoh_router


@launch_this
def orbbec_gemini_335l(
    camera: str = 'camera_0',
    color_width_pixels: int = 640,
    color_height_pixels: int = 480,
    color_frames_per_second: int = 30,
    jpeg_quality: int = 80,
    enable_depth: bool = True,
    depth_width_pixels: int = 848,
    depth_height_pixels: int = 480,
    depth_frames_per_second: int = DEFAULT_DEPTH_FRAMES_PER_SECOND,
    depth_decimation: int = 2,
    point_cloud_enabled: bool = True,
):
    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    with bl.group(f'sensors/{camera}'):
        bl.node(
            package='robot_drivers',
            executable='orbbec_gemini_335l',
            name='orbbec_gemini_335l',
            params={
                'color_width_pixels': color_width_pixels,
                'color_height_pixels': color_height_pixels,
                'color_frames_per_second': color_frames_per_second,
                'jpeg_quality': jpeg_quality,
                'enable_depth': enable_depth,
                'depth_width_pixels': depth_width_pixels,
                'depth_height_pixels': depth_height_pixels,
                'depth_frames_per_second': depth_frames_per_second,
                'depth_decimation': depth_decimation,
            },
            **RESPAWN,
        )
        if enable_depth and point_cloud_enabled:
            bl.node(
                package='depth_image_proc',
                executable='point_cloud_xyz_node',
                name='depth_to_point_cloud',
                remaps={
                    'image_rect': 'depth/image_raw',
                    'camera_info': 'depth/camera_info',
                    'points': 'depth/points',
                },
                **RESPAWN,
            )
