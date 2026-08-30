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
def audio(robot: str = 'taro'):
    bl = BetterLaunch()
    bl.node(
        package='audio_common',
        executable='audio_player_node',
        name='audio_player_node',
        params={'channels': 1},
        **RESPAWN,
    )
    bl.node(
        package='robot_drivers',
        executable='reverse_beeper',
        name='reverse_beeper',
        params={'cmd_vel_topic': f'/{robot}/platform/cmd_vel'},
        **RESPAWN,
    )
