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

CONE_ROWS_TOPIC = '/perception/cone_rows'
COLOR_IMAGE_TOPIC = '/sensors/camera_0/color/image_raw/compressed'


@launch_this
def row_follow(target_offset: float = 0.0):
    bl = BetterLaunch()
    bl.node(
        package='robot_perception',
        executable='row_detector',
        name='cone_row_detector',
        params={
            'image_topic': COLOR_IMAGE_TOPIC,
            'class_label': 'cone_row',
            'hue_min': 2.0,
            'hue_max': 25.0,
            'min_saturation': 0.45,
            'min_value': 0.30,
            'min_fraction': 0.02,
            'min_row_width': 0.02,
            'roi_top': 0.4,
            'roi_bottom': 0.95,
        },
        remaps={'detections': CONE_ROWS_TOPIC},
    )
    bl.node(
        package='robot_perception',
        executable='row_follow',
        name='row_follow',
        params={'target_offset': target_offset},
        remaps={'detections': CONE_ROWS_TOPIC},
    )
