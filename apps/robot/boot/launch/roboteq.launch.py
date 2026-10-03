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
CONNECT_PROBE_TIMEOUT_SECONDS = 0.2
ROUTER_POLL_INTERVAL_SECONDS = 0.2
RESPAWN = {'max_respawns': -1, 'respawn_delay': 2.0}


def router_is_listening():
    try:
        socket.create_connection(
            ('127.0.0.1', ZENOH_ROUTER_PORT),
            timeout=CONNECT_PROBE_TIMEOUT_SECONDS).close()
        return True
    except OSError:
        return False


def wait_for_router(attempts=50):
    for _ in range(attempts):
        if router_is_listening():
            return
        time.sleep(ROUTER_POLL_INTERVAL_SECONDS)


@launch_this
def roboteq(
    port: str = '/dev/cu.usbmodem2072356748451',
    baud: int = 115200,
    counts_per_revolution: int = 90,
):
    bl = BetterLaunch()
    if not router_is_listening():
        bl.process(
            '.pixi/envs/default/lib/rmw_zenoh_cpp/rmw_zenohd',
            name='zenoh_router',
            **RESPAWN,
        )
        wait_for_router()
    bl.node(
        package='robot_drivers',
        executable='roboteq_motor_driver',
        name='roboteq_motor_driver',
        params={
            'serial_port': port,
            'baud_rate': baud,
            'counts_per_revolution': counts_per_revolution,
        },
        **RESPAWN,
    )
