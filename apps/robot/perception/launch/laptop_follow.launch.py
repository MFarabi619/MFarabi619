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

LAPTOP_TOPIC = '/perception/laptop'
CAMERA = '/sensors/camera_0'


@launch_this
def laptop_follow(standoff_distance: float = 0.25, reacquire_frames: int = 8):
    bl = BetterLaunch()
    bl.node(
        package='robot_perception',
        executable='color_blob_detector',
        name='laptop_detector',
        params={
            'image_topic': f'{CAMERA}/color/image_raw/compressed',
            'depth_topic': f'{CAMERA}/depth/image_raw',
            'depth_camera_info_topic': f'{CAMERA}/depth/camera_info',
            'class_label': 'laptop',
            'hue_min': 20.0,
            'hue_max': 35.0,
            'min_saturation': 0.45,
            'min_value': 0.35,
            'min_area': 800,
            'min_triangularity': 0.0,
            'min_aspect_ratio': 0.0,
            'fallback_range': 3.0,
            'overlay_topic': '/perception/laptop/overlay',
        },
        remaps={'detections': LAPTOP_TOPIC},
    )
    bl.node(
        package='robot_perception',
        executable='approach',
        name='laptop_approach',
        params={
            'standoff_distance': standoff_distance,
            'reacquire_frames': reacquire_frames,
            'scene_topic': '/perception/laptop/scene',
        },
        remaps={'detections': LAPTOP_TOPIC},
    )
