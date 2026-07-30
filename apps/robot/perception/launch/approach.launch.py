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

CONES_TOPIC = '/perception/cones'


@launch_this
def approach(standoff_distance: float = 1.0):
    bl = BetterLaunch()
    bl.node(
        package='robot_perception',
        executable='cone_detector',
        name='cone_detector',
        remaps={'detections': CONES_TOPIC},
    )
    bl.node(
        package='robot_perception',
        executable='approach',
        name='approach',
        params={'standoff_distance': standoff_distance},
        remaps={'detections': CONES_TOPIC},
    )
