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

DETECTIONS_TOPIC = 'perception/line/detections'


@launch_this
def line_follow(
    camera: str = 'camera_0',
    start_enabled: bool = False,
    params_file: str = '',
    overrides_file: str = '',
):
    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    params_file = params_file or bl.find('robot_perception', 'line_follow.yaml')
    param_files = [params_file] + ([overrides_file] if overrides_file else [])
    bl.node(
        package='robot_perception',
        executable='color_blob_detector',
        name='line_detector',
        params={
            'image_topic': f'sensors/{camera}/color/image_raw/compressed',
            'depth_topic': f'sensors/{camera}/depth/image_raw',
            'depth_camera_info_topic': f'sensors/{camera}/depth/camera_info',
            'detections_topic': DETECTIONS_TOPIC,
            'overlay_topic': 'perception/line/overlay',
            'class_label': 'line',
            'start_enabled': start_enabled,
        },
        param_files=param_files,
        **RESPAWN,
    )
    bl.node(
        package='robot_perception',
        executable='line_follow',
        name='line_follow',
        params={
            'detections_topic': DETECTIONS_TOPIC,
            'start_enabled': start_enabled,
        },
        param_files=param_files,
        **RESPAWN,
    )
