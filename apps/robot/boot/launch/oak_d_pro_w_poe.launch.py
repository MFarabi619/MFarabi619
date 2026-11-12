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
def oak_d_pro_w_poe(
    camera: str = 'camera_0',
    ip: str = '',
    depth_fps: float = 30.0,
    color_fps: float = 60.0,
    jpeg_quality: int = 60,
    color_resolution_divisor: int = 2,
    depth_resolution_divisor: int = 4,
    detects_on_camera: bool = False,
    model_path: str = '',
):
    bl = BetterLaunch()
    ensure_router(bl)
    optical_frame = f'{camera}_link_color_optical_frame'
    parameters = {
        'frame_id': optical_frame,
        'ip': ip,
        'depth_fps': depth_fps,
        'color_fps': color_fps,
        'jpeg_quality': jpeg_quality,
        'color_resolution_divisor': color_resolution_divisor,
        'depth_resolution_divisor': depth_resolution_divisor,
    }
    if detects_on_camera:
        parameters['model_path'] = model_path
    bl.node(
        package='robot_drivers',
        executable='oak_d_pro_w_poe_spatial' if detects_on_camera else 'oak_d_pro_w_poe',
        name='oak_d_pro_w_poe',
        params=parameters,
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
