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
from robot_boot.launch_policy import RESPAWN
from robot_boot.zenoh_router import (
    ZENOH_LOCAL_ROUTER_CLIENT_CONFIG_OVERRIDE, ZENOH_ROUTER_PORT, ensure_zenoh_router)
from robot_machines.machine import load_machine

CONNECT_TIMEOUT_MILLISECONDS = 3000


def robot_hostname(robot_name):
    return load_machine(robot_name).hostname


def bridging_peer_config_override(robot_name):
    return (
        'mode="peer";connect/endpoints='
        f'["tcp/localhost:{ZENOH_ROUTER_PORT}",'
        f'"tcp/{robot_hostname(robot_name)}.local:{ZENOH_ROUTER_PORT}"];'
        f'connect/timeout_ms={CONNECT_TIMEOUT_MILLISECONDS}')


@launch_this
def voice(robot: str = 'taro'):
    bl = BetterLaunch()
    ensure_zenoh_router(bl)
    bl.node(
        package='audio_common',
        executable='audio_capturer_node',
        name='audio_capturer_node',
        remaps={'audio': 'microphone/audio'},
        env={'ZENOH_CONFIG_OVERRIDE': ZENOH_LOCAL_ROUTER_CLIENT_CONFIG_OVERRIDE},
        **RESPAWN,
    )
    bl.node(
        package='robot_perception',
        executable='voice_word_detector',
        name='voice_word_detector',
        params={'start_enabled': True},
        env={'ZENOH_CONFIG_OVERRIDE': ZENOH_LOCAL_ROUTER_CLIENT_CONFIG_OVERRIDE},
        **RESPAWN,
    )
    bl.node(
        package='robot_perception',
        executable='voice_transcriber',
        name='voice_transcriber',
        params={'start_enabled': True},
        env={'ZENOH_CONFIG_OVERRIDE': ZENOH_LOCAL_ROUTER_CLIENT_CONFIG_OVERRIDE},
        **RESPAWN,
    )
    bl.node(
        package='robot_perception',
        executable='voice_teleop',
        name='voice_teleop',
        params={'start_enabled': True},
        remaps={'/joy_teleop/cmd_vel': f'/{robot}/joy_teleop/cmd_vel'},
        env={'ZENOH_CONFIG_OVERRIDE': bridging_peer_config_override(robot)},
        **RESPAWN,
    )
    bl.node(
        package='robot_perception',
        executable='voice_speaker',
        name='voice_speaker',
        env={'ZENOH_CONFIG_OVERRIDE': ZENOH_LOCAL_ROUTER_CLIENT_CONFIG_OVERRIDE},
        **RESPAWN,
    )
    bl.node(
        package='audio_common',
        executable='audio_player_node',
        name='audio_player_node',
        params={'channels': 1},
        env={'ZENOH_CONFIG_OVERRIDE': ZENOH_LOCAL_ROUTER_CLIENT_CONFIG_OVERRIDE},
        **RESPAWN,
    )
