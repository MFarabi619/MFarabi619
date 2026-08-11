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

SIDEWALK_TOPIC = '/perception/sidewalk'
COLOR_IMAGE_TOPIC = '/sensors/camera_0/color/image_raw/compressed'


@launch_this
def sidewalk_follow(target_offset: float = 0.0):
    bl = BetterLaunch()
    bl.node(
        package='robot_perception',
        executable='sidewalk_detector',
        name='sidewalk_detector',
        params={'image_topic': COLOR_IMAGE_TOPIC},
        remaps={'detections': SIDEWALK_TOPIC},
    )
    bl.node(
        package='robot_perception',
        executable='row_follow',
        name='sidewalk_follow',
        params={'target_offset': target_offset},
        remaps={'detections': SIDEWALK_TOPIC},
    )
