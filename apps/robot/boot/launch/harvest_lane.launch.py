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

RESPAWN = {'max_respawns': -1, 'respawn_delay': 2.0}


@launch_this
def harvest_lane():
    bl = BetterLaunch()
    bl.node(
        package='robot_perception',
        executable='canopy_detector',
        name='canopy_detector',
        **RESPAWN,
    )
    bl.node(
        package='robot_perception',
        executable='harvest_lane_navigator',
        name='harvest_lane_navigator',
        params={
            'start_enabled': True,
            'odom_topic': '/diff_drive_controller/odom',
            'forward_speed_mps': 0.3,
            'max_angular_speed_radps': 0.6,
            'command_smoothing_seconds': 0.1,
        },
        **RESPAWN,
    )
    bl.node(
        package='robot_perception',
        executable='row_shuttle',
        name='row_shuttle',
        **RESPAWN,
    )
    bl.node(
        package='nav2_behaviors',
        executable='behavior_server',
        name='behavior_server',
        param_files=['navigation/config/behaviors.yaml'],
        **RESPAWN,
    )
