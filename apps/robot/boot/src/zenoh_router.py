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

from robot_boot.launch_policy import RESPAWN

ZENOH_ROUTER_EXECUTABLE = 'rmw_zenohd'
ZENOH_ROUTER_PORT = 7447
ZENOH_ROUTER_CONNECT_PROBE_TIMEOUT_SECONDS = 0.2
ZENOH_ROUTER_MAX_ATTEMPTS = 50
ZENOH_ROUTER_RETRY_DELAY_SECONDS = 0.2
ZENOH_ROUTER_CONFIG_OVERRIDE = 'mode="router"'
ZENOH_CLIENT_CONFIG_OVERRIDE = 'mode="client"'
ZENOH_LOCAL_ROUTER_CLIENT_CONFIG_OVERRIDE = (
    f'mode="client";connect/endpoints=["tcp/localhost:{ZENOH_ROUTER_PORT}"]')


def zenoh_router_is_listening():
    try:
        socket.create_connection(
            ('127.0.0.1', ZENOH_ROUTER_PORT),
            timeout=ZENOH_ROUTER_CONNECT_PROBE_TIMEOUT_SECONDS).close()
        return True
    except OSError:
        return False


def wait_for_zenoh_router(
        max_attempts=ZENOH_ROUTER_MAX_ATTEMPTS,
        retry_delay_seconds=ZENOH_ROUTER_RETRY_DELAY_SECONDS):
    for _ in range(max_attempts):
        if zenoh_router_is_listening():
            return True
        time.sleep(retry_delay_seconds)
    return False


def start_zenoh_router(bl, env=None):
    bl.node(
        package='rmw_zenoh_cpp',
        executable=ZENOH_ROUTER_EXECUTABLE,
        name='zenoh_router',
        raw=True,
        ros_waittime=None,
        env=env,
        **RESPAWN,
    )


def ensure_zenoh_router(
        bl, env=None, max_attempts=ZENOH_ROUTER_MAX_ATTEMPTS,
        retry_delay_seconds=ZENOH_ROUTER_RETRY_DELAY_SECONDS):
    if not zenoh_router_is_listening():
        start_zenoh_router(bl, env)
    wait_for_zenoh_router(max_attempts, retry_delay_seconds)
