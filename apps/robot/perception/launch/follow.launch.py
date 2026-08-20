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

OPERATOR_TOPIC = '/perception/operator'


@launch_this
def follow(standoff_distance: float = 1.5, max_missing_frames: int = 8):
    bl = BetterLaunch()
    bl.node(
        package='robot_perception',
        executable='green_detector',
        name='green_detector',
        remaps={'detections': OPERATOR_TOPIC},
    )
    bl.node(
        package='robot_perception',
        executable='tracked_approach',
        name='operator_follow',
        params={
            'standoff_distance': standoff_distance,
            'max_missing_frames': max_missing_frames,
        },
        remaps={'detections': OPERATOR_TOPIC},
    )
