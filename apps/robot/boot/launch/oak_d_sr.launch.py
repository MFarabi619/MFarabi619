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
def oak_d_sr(
    camera: str = 'camera_0',
    fps: float = 15.0,
    jpeg_quality: int = 60,
    point_cloud: bool = True,
):
    bl = BetterLaunch()
    ensure_router(bl)
    optical_frame = f'{camera}_link_right_camera_optical_frame'
    bl.node(
        package='robot_drivers',
        executable='oak_d_sr',
        name='oak_d_sr',
        params={
            'frame_id': optical_frame,
            'fps': fps,
            'jpeg_quality': jpeg_quality,
        },
        remaps={
            'color/image_raw/compressed': f'sensors/{camera}/color/image_raw/compressed',
            'color/camera_info': f'sensors/{camera}/color/camera_info',
            'depth/image_raw': f'sensors/{camera}/depth/image_raw',
            'depth/image_raw/compressed': f'sensors/{camera}/depth/image_raw/compressed',
            'depth/camera_info': f'sensors/{camera}/depth/camera_info',
            'depth/points': f'sensors/{camera}/depth/points',
            'imu/data': f'sensors/{camera}/imu/data',
        },
        **RESPAWN,
    )
    bl.node(
        package='tf2_ros',
        executable='static_transform_publisher',
        name='oak_d_optical_frame_publisher',
        cmd_args=[
            '--roll', '-1.5708', '--yaw', '-1.5708',
            '--frame-id', f'{camera}_link',
            '--child-frame-id', optical_frame,
        ],
        remaps=TF_REMAPS,
        **RESPAWN,
    )
    if point_cloud:
        bl.node(
            package='depth_image_proc',
            executable='point_cloud_xyz_node',
            name='oak_d_sr_depth_to_pointcloud',
            remaps={
                'image_rect': f'sensors/{camera}/depth/image_raw',
                'camera_info': f'sensors/{camera}/depth/camera_info',
                'points': f'sensors/{camera}/depth/points',
            },
            **RESPAWN,
        )
