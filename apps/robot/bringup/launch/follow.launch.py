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
def follow(
        max_forward_speed: float = 2.0, max_missing_frames: int = 24,
        max_angular_speed: float = 3.0, steer_gain: float = 3.0,
        steer_damping: float = 0.55, distance_damping: float = 0.4,
        command_smoothing: float = 0.6, steer_deadband: float = 0.05,
        lost_spin_decay: float = 1.0, max_retreat_speed: float = 1.5):
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
            'max_missing_frames': max_missing_frames,
            'start_enabled': True,
            'max_forward_speed': max_forward_speed,
            'max_angular_speed': max_angular_speed,
            'max_retreat_speed': max_retreat_speed,
            'distance_gain': 2.5,
            'distance_damping': distance_damping,
            'steer_gain': steer_gain,
            'steer_damping': steer_damping,
            'command_smoothing': command_smoothing,
            'distance_deadband': 0.1,
            'steer_deadband': steer_deadband,
            'lost_spin_decay': lost_spin_decay,
        },
        **RESPAWN,
    )
