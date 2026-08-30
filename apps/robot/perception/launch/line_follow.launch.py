#!/usr/bin/env python3

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

@launch_this
def line_follow(robot: str = 'jiro', target_offset: float = 0.0):
    bl = BetterLaunch()
    camera_namespace = f'/{robot}/sensors/camera_0'
    line_topic = f'/{robot}/perception/line'
    bl.node(
        package='robot_perception',
        executable='color_blob_detector',
        name='line_detector',
        params={
            'image_topic': f'{camera_namespace}/color/image_raw/compressed',
            'depth_topic': f'{camera_namespace}/depth/image_raw',
            'depth_camera_info_topic': f'{camera_namespace}/depth/camera_info',
            'class_label': 'line',
            'hue_min': 0.0,
            'hue_max': 180.0,
            'min_saturation': 0.0,
            'max_saturation': 0.25,
            'min_value': 0.6,
            'min_triangularity': 0.0,
            'min_aspect_ratio': 0.0,
            'min_area': 800,
            'roi_top_fraction': 0.55,
            'start_enabled': True,
        },
        remaps={
            'detections': line_topic,
            'perception/vision/overlay': f'/{robot}/perception/line/overlay',
        },
    )
    bl.node(
        package='robot_perception',
        executable='row_follow',
        name='line_follow',
        params={'target_offset': target_offset, 'image_width': 640},
        remaps={
            'detections': line_topic,
            'cmd_vel': f'/{robot}/cmd_vel',
        },
    )
