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
def surface_follow(
    surface: str = 'sidewalk',
    camera: str = 'camera_0',
    camera_height_m: float = 0.0,
    start_enabled: bool = False,
    params_file: str = '',
    overrides_file: str = '',
):
    bl = BetterLaunch()
    ensure_router(bl)
    params_file = params_file or bl.find('robot_perception', 'surface_follow.yaml')
    param_files = [params_file] + ([overrides_file] if overrides_file else [])
    detections_topic = f'perception/{surface}/detections'
    bl.node(
        package='robot_perception',
        executable='surface_detector',
        name=f'{surface}_detector',
        params={
            'image_topic': f'sensors/{camera}/color/image_raw/compressed',
            'detections_topic': detections_topic,
            'overlay_topic': f'perception/{surface}/overlay',
            'class_label': surface,
        },
        param_files=param_files,
        **RESPAWN,
    )
    bl.node(
        package='robot_perception',
        executable='surface_follow',
        name=f'{surface}_follow',
        params={
            'detections_topic': detections_topic,
            'camera_info_topic': f'sensors/{camera}/color/camera_info',
            'camera_height_m': camera_height_m,
            'start_enabled': start_enabled,
        },
        param_files=param_files,
        **RESPAWN,
    )
