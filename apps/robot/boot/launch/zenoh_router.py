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

ROUTER_PORT = 7447
CONNECT_PROBE_TIMEOUT_SECONDS = 0.2
RESPAWN = {'max_respawns': -1, 'respawn_delay': 2.0}


def router_is_listening():
    try:
        socket.create_connection(
            ('127.0.0.1', ROUTER_PORT),
            timeout=CONNECT_PROBE_TIMEOUT_SECONDS).close()
        return True
    except OSError:
        return False


def wait_for_router(attempts=50, poll_seconds=0.2):
    for _ in range(attempts):
        if router_is_listening():
            return True
        time.sleep(poll_seconds)
    return False


def ensure_router(bl, env=None, attempts=50, poll_seconds=0.2):
    if not router_is_listening():
        bl.node(
            package='rmw_zenoh_cpp',
            executable='rmw_zenohd',
            name='zenoh_router',
            raw=True,
            ros_waittime=None,
            env=env,
            **RESPAWN,
        )
    return wait_for_router(attempts, poll_seconds)
