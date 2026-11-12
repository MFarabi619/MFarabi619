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

MASK_TOPIC = 'perception/canopy/mask/compressed'


@launch_this
def harvest_lane(
    camera: str = 'camera_0',
    camera_height_m: float = 0.0,
    camera_lateral_offset_m: float = 0.0,
    odom_topic: str = 'diff_drive_controller/odom',
    start_enabled: bool = False,
    overrides_file: str = '',
):
    bl = BetterLaunch()
    ensure_router(bl)
    param_files = [overrides_file] if overrides_file else []
    bl.node(
        package='robot_perception',
        executable='canopy_detector',
        name='canopy_detector',
        params={
            'image_topic': f'sensors/{camera}/color/image_raw/compressed',
            'mask_topic': MASK_TOPIC,
            'fraction_topic': 'perception/canopy/fraction',
        },
        param_files=param_files,
        **RESPAWN,
    )
    bl.node(
        package='robot_perception',
        executable='harvest_lane_navigator',
        name='harvest_lane_navigator',
        params={
            'mask_topic': MASK_TOPIC,
            'camera_info_topic': f'sensors/{camera}/color/camera_info',
            'depth_topic': f'sensors/{camera}/depth/image_raw',
            'odom_topic': odom_topic,
            'camera_height_m': camera_height_m,
            'camera_lateral_offset_m': camera_lateral_offset_m,
            'start_enabled': start_enabled,
        },
        param_files=param_files,
        **RESPAWN,
    )
