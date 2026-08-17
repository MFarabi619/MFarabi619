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


import os

from better_launch import BetterLaunch, launch_this

OPERATOR_TOPIC = '/perception/operator'
COLOR_IMAGE_TOPIC = '/sensors/camera_0/color/image_raw'
CAMERA_INFO_TOPIC = '/sensors/camera_0/color/camera_info'
CAMERA_FRAME = 'camera_0_color_optical_frame'
PIXI = os.path.expanduser('~/.pixi/bin/pixi')


@launch_this
def apriltag_follow(
        standoff_distance: float = 1.5,
        camera_frame: str = CAMERA_FRAME,
        max_missing_frames: int = 8):
    bl = BetterLaunch()
    bl.process(
        f'{PIXI} run --clean-env -e jazzy'
        ' ros2 run apriltag_ros apriltag_node --ros-args'
        ' --params-file perception/config/apriltag.yaml'
        f' -r image_rect:={COLOR_IMAGE_TOPIC}'
        f' -r image_rect/compressed:={COLOR_IMAGE_TOPIC}/compressed'
        f' -r camera_info:={CAMERA_INFO_TOPIC}'
        ' -r detections:=/perception/apriltag/detections',
        name='apriltag_node',
        env={'HOME': os.environ['HOME'],
             'ZENOH_CONFIG_OVERRIDE': os.environ.get('ZENOH_CONFIG_OVERRIDE', '')},
        isolate_env=True,
        max_respawns=-1,
        respawn_delay=2.0,
    )
    bl.node(
        package='robot_perception',
        executable='apriltag_operator_adapter',
        name='apriltag_operator_adapter',
        params={'camera_frame': camera_frame},
        remaps={'detections': OPERATOR_TOPIC},
    )
    bl.node(
        package='robot_perception',
        executable='approach',
        name='operator_approach',
        params={
            'standoff_distance': standoff_distance,
            'max_missing_frames': max_missing_frames,
        },
        remaps={'detections': OPERATOR_TOPIC},
    )
