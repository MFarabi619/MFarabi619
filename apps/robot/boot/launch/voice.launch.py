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


import socket
import time

from better_launch import BetterLaunch, launch_this

ZENOH_ROUTER_PORT = 7447
ROUTER_CONFIG_OVERRIDE = (
    f'connect/endpoints=["tcp/rpi5-16-2.local:{ZENOH_ROUTER_PORT}",'
    f'"tcp/rpi5-16.local:{ZENOH_ROUTER_PORT}",'
    f'"tcp/beagleyai.local:{ZENOH_ROUTER_PORT}"]')
CLIENT_CONFIG_OVERRIDE = f'mode="client";connect/endpoints=["tcp/localhost:{ZENOH_ROUTER_PORT}"]'

RESPAWN = {'max_respawns': -1, 'respawn_delay': 2.0}


def router_is_listening():
    try:
        socket.create_connection(
            ('127.0.0.1', ZENOH_ROUTER_PORT), timeout=0.2).close()
        return True
    except OSError:
        return False


def wait_for_router(attempts=50):
    for _ in range(attempts):
        if router_is_listening():
            return
        time.sleep(0.2)


@launch_this
def voice(robot: str = 'taro'):
    bl = BetterLaunch()
    if not router_is_listening():
        bl.process(
            'ros2 run rmw_zenoh_cpp rmw_zenohd',
            name='zenoh_router',
            env={'ZENOH_CONFIG_OVERRIDE': ROUTER_CONFIG_OVERRIDE},
            **RESPAWN,
        )
        wait_for_router()
    bl.node(
        package='audio_common',
        executable='audio_capturer_node',
        name='audio_capturer_node',
        remaps={'audio': 'microphone/audio'},
        env={'ZENOH_CONFIG_OVERRIDE': CLIENT_CONFIG_OVERRIDE},
        **RESPAWN,
    )
    bl.node(
        package='robot_perception',
        executable='voice_word_detector',
        name='voice_word_detector',
        params={'start_enabled': True},
        env={'ZENOH_CONFIG_OVERRIDE': CLIENT_CONFIG_OVERRIDE},
        **RESPAWN,
    )
    bl.node(
        package='robot_perception',
        executable='voice_teleop',
        name='voice_teleop',
        params={'start_enabled': True},
        remaps={'/joy_teleop/cmd_vel': f'/{robot}/joy_teleop/cmd_vel'},
        env={'ZENOH_CONFIG_OVERRIDE': CLIENT_CONFIG_OVERRIDE},
        **RESPAWN,
    )
    bl.node(
        package='robot_perception',
        executable='voice_speaker',
        name='voice_speaker',
        env={'ZENOH_CONFIG_OVERRIDE': CLIENT_CONFIG_OVERRIDE},
        **RESPAWN,
    )
    bl.node(
        package='audio_common',
        executable='audio_player_node',
        name='audio_player_node',
        params={'channels': 1},
        env={'ZENOH_CONFIG_OVERRIDE': CLIENT_CONFIG_OVERRIDE},
        **RESPAWN,
    )
