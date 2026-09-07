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


import os
import socket
import time

from better_launch import BetterLaunch, launch_this
from pygnssutils import OUTPUT_SERIAL

ZENOH_ROUTER_PORT = 7447
CONNECT_PROBE_TIMEOUT_SECONDS = 0.2
ROUTER_POLL_INTERVAL_SECONDS = 0.2
RESPAWN = {'max_respawns': -1, 'respawn_delay': 2.0}
NTRIP_RESPAWN = {'max_respawns': -1, 'respawn_delay': 10.0}
NTRIP_CASTER_HOST = 'rtk2go.com'
GPS_TOPICS = ['fix', 'vel', 'time_reference', 'heading']


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
def gps(
    port: str = '/dev/cu.usbmodem2101',
    baud: int = 115200,
    mountpoint: str = 'OsgoodeFarms',
    ntrip_username: str = 'farabi@tandemrobotics.ca',
):
    bl = BetterLaunch()
    if not router_is_listening():
        bl.process(
            '.pixi/envs/jazzy/lib/rmw_zenoh_cpp/rmw_zenohd',
            name='zenoh_router',
            env={'HOME': os.environ['HOME']},
            isolate_env=True,
            **RESPAWN,
        )
        wait_for_router()
    if mountpoint:
        bl.process(
            ['gnssntripclient', '--server', NTRIP_CASTER_HOST,
             '--ntripversion', '1.0', '--mountpoint', mountpoint,
             '--ntripuser', ntrip_username, '--ntrippassword', 'none',
             '--clioutput', str(OUTPUT_SERIAL), '--output', f'{port}@{baud}'],
            name='ntrip_client',
            **NTRIP_RESPAWN,
        )
    bl.node(
        package='nmea_navsat_driver',
        executable='nmea_serial_driver',
        name='nmea_navsat_driver',
        params={'port': port, 'baud': baud, 'frame_id': 'gps_link'},
        remaps={topic: f'sensors/gps_0/{topic}' for topic in GPS_TOPICS},
        **RESPAWN,
    )
