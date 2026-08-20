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


def wait_for_router(attempts=50):
    for _ in range(attempts):
        try:
            socket.create_connection(
                ('127.0.0.1', ZENOH_ROUTER_PORT), timeout=0.2).close()
            return
        except OSError:
            time.sleep(0.2)


@launch_this
def boot(gesture_camera: str = 'webcam', robot: str = 'taro'):
    bl = BetterLaunch()
    gesture_camera_topics = {
        'webcam': '/image',
        'robot': f'/{robot}/sensors/camera_0/color/image_raw/compressed',
    }
    bl.process(
        'ros2 run rmw_zenoh_cpp rmw_zenohd',
        name='zenoh_router',
        env={'ZENOH_CONFIG_OVERRIDE': ROUTER_CONFIG_OVERRIDE},
        max_respawns=-1,
        respawn_delay=2.0,
    )
    wait_for_router()
    bl.node(
        package='foxglove_bridge',
        executable='foxglove_bridge',
        name='foxglove_bridge',
        params={
            'send_buffer_limit': 1000000,
            'max_qos_depth': 5,
            'best_effort_qos_topic_whitelist': [f'/{robot}/sensors/camera_0/.*'],
        },
        env={'ZENOH_CONFIG_OVERRIDE': CLIENT_CONFIG_OVERRIDE},
        max_respawns=-1,
        respawn_delay=2.0,
    )
    bl.node(
        package='robot_perception',
        executable='gesture_teleop',
        name='gesture_teleop',
        params={'image_topic': gesture_camera_topics[gesture_camera]},
        env={'ZENOH_CONFIG_OVERRIDE': CLIENT_CONFIG_OVERRIDE},
    )
    bl.node(
        package='robot_perception',
        executable='gesture_to_cmd_vel',
        name='gesture_to_cmd_vel',
        remaps={'/joy_teleop/cmd_vel': f'/{robot}/joy_teleop/cmd_vel'},
        env={'ZENOH_CONFIG_OVERRIDE': CLIENT_CONFIG_OVERRIDE},
    )
    bl.node(
        package='robot_perception',
        executable='foxglove_panels',
        name='foxglove_panels',
        env={'ZENOH_CONFIG_OVERRIDE': CLIENT_CONFIG_OVERRIDE},
    )
