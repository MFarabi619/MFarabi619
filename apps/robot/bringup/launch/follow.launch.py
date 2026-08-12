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
def follow():
    bl = BetterLaunch()
    bl.node(
        package='robot_perception',
        executable='person_detector',
        name='person_detector',
        params={'min_score': 0.3},
        **RESPAWN,
    )
    bl.node(
        package='robot_perception',
        executable='approach',
        name='person_approach',
        params={
            'standoff_distance': 1.5,
            'reacquire_frames': 24,
            'start_enabled': True,
            'max_forward_speed': 2.0,
            'max_angular_speed': 3.0,
            'max_retreat_speed': 1.5,
            'distance_gain': 2.5,
            'distance_damping': 0.4,
            'steer_gain': 3.0,
            'steer_damping': 0.55,
            'command_smoothing': 0.6,
            'distance_deadband': 0.1,
            'steer_deadband': 0.05,
        },
        **RESPAWN,
    )
