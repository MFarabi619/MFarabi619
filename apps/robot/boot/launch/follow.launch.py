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
        detector: str = 'ssd_mobilenet',
        max_forward_speed: float = 2.0, max_missing_frames: int = 24,
        max_angular_speed: float = 3.0, steer_gain: float = 3.0,
        steer_damping: float = 0.55, distance_damping: float = 0.4,
        command_smoothing_seconds: float = 0.1, steer_deadband: float = 0.05,
        reacquire_angular_decay: float = 1.0, max_backward_speed: float = 2.0):
    bl = BetterLaunch()
    bl.node(
        package='robot_perception',
        executable=f'{detector}_person_detector',
        name='person_detector',
        params={'min_score': 0.3},
        **RESPAWN,
    )
    if detector == 'ssd_mobilenet':
        approach_executable = 'approach'
        target_loss_parameters = {}
    else:
        approach_executable = 'tracked_approach'
        target_loss_parameters = {
            'reacquire_angular_decay': reacquire_angular_decay,
        }
    bl.node(
        package='robot_perception',
        executable=approach_executable,
        name='person_follow',
        params={
            'standoff_distance': 1.5,
            'start_enabled': True,
            'max_forward_speed': max_forward_speed,
            'max_angular_speed': max_angular_speed,
            'max_backward_speed': max_backward_speed,
            'distance_gain': 2.5,
            'distance_damping': distance_damping,
            'steer_gain': steer_gain,
            'steer_damping': steer_damping,
            'command_smoothing_seconds': command_smoothing_seconds,
            'distance_deadband': 0.1,
            'steer_deadband': steer_deadband,
            'max_missing_frames': max_missing_frames,
            **target_loss_parameters,
        },
        **RESPAWN,
    )
