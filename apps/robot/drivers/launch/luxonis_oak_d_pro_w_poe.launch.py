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
def luxonis_oak_d_pro_w_poe(
    camera: str = 'camera_0',
    ip: str = '',
    depth_frames_per_second: float = 30.0,
    color_frames_per_second: float = 60.0,
    jpeg_quality: int = 60,
    color_resolution_divisor: int = 2,
    depth_resolution_divisor: int = 4,
    detects_on_camera: bool = False,
    model_path: str = '',
):
    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    parameters = {
        'frame_id': f'{camera}_color_optical_frame',
        'ip': ip,
        'depth_frames_per_second': depth_frames_per_second,
        'color_frames_per_second': color_frames_per_second,
        'jpeg_quality': jpeg_quality,
        'color_resolution_divisor': color_resolution_divisor,
        'depth_resolution_divisor': depth_resolution_divisor,
    }
    if detects_on_camera:
        parameters['model_path'] = model_path
    with bl.group(f'sensors/{camera}'):
        bl.node(
            package='robot_drivers',
            executable=(
                'luxonis_oak_d_pro_w_poe_spatial' if detects_on_camera
                else 'luxonis_oak_d_pro_w_poe'),
            name='luxonis_oak_d_pro_w_poe',
            params=parameters,
            **RESPAWN,
        )
